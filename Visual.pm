# $Id: Visual.pm,v 0.04 2003/01/14 23:00:18 lunartear Exp $
# Copyrights and documentation are after __END__.
package Term::Visual;

use strict;
use warnings;
use vars qw($VERSION $console);
$VERSION = (qw($Revision: 0.04 $ ))[1];

use Term::Visual::StatusBar;
use POE qw(Wheel::Curses Wheel::ReadWrite ); 
use Curses;
use Carp;

sub DEBUG       () { 0 }
sub TESTING     () { 0 }

if (DEBUG) { open ERRS, ">error_file"; }

### Term::Visual Constants.

sub WINDOW      () { 0 } # hash of windows and there properties
sub WINDOW_REV  () { 1 } # window name => id key value pair for reverse lookups
sub PALETTE     () { 2 } # Palette Element
sub PAL_COL_SEQ () { 3 } # Palette Color Sequence
sub CUR_WIN     () { 4 } # holds the current window id
sub ERRLEVEL    () { 5 } # Visterm's Error Level boolean 

### Palette Constants.

sub PAL_PAIR    () { 0 }  # Index of the COLOR_PAIR in the palette.
sub PAL_NUMBER  () { 1 }  # Index of the color number in the palette.
sub PAL_DESC    () { 2 }  # Text description of the color.

### Title line constants.

sub TITLE_LINE  () { 0 }  # Where the title goes.
sub TITLE_COL   () { 0 }


sub current_window { # should this be seperated into 2 functions
  if (DEBUG) { print ERRS " Enter current_window\n"; }
  my $self = shift;
  if (@_) {
    my $query = shift;
    my $validity = validate_window($self, $query);
    if ($validity) { $self->[CUR_WIN] = $query; }
  }
  return $self->[CUR_WIN];
}


sub CREATE_WINDOW_ID {
  if (DEBUG) { print ERRS "Enter CREATE_WINDOW_ID\n"; }
  my $self = shift;
  my $id = 0;
  my @list = sort {$a <=> $b} keys %{$self->[WINDOW]};
  if (@list) {
    my $high_number = $list[$#list] + 1;
    for my $i (0..$high_number) {
      next if (defined $list[$i] && $i == $list[$i]);
      $id = $i; last;
    }
  }
  return $id;
}


### Mold the Object.

sub new {
  if (DEBUG) { print ERRS "Enter Visterm->new\n"; }
  my $package = shift;
  my %params = @_;
  my $alias = delete $params{Alias};
  my $errlevel = delete $params{Errlevel} || 0;
  my $current_window = -1;

  my $self =
    bless [ { }, # WINDOW stores window properties under each window id.
            { }, # WINDOW_REV reverse window lookups.
            { }, # Palette
              0, # Palette Color Sequence
             $current_window,
             $errlevel # Visterms error level.
          ], $package;

  POE::Session->create
    ( object_states => 
      [ $self =>   # $_[OBJECT]
      {                 _start => "start_terminal",
                         _stop => "terminal_stopped",
                 send_me_input => "register_input",
                 private_input => "got_curses_input",
                    got_stderr => "got_stderr",
      } ],
      args => [ $alias ], 
       
    );

  return $self;
}

sub got_stderr {
  my ($self, $kernel, $stderr_line) = @_[OBJECT, KERNEL, ARG0];
  my $window_id = $self->[CUR_WIN];

if (DEBUG) {  print ERRS $stderr_line, "\n"; } 

     &print($self, $window_id,
           "\0(stderr_bullet)" .
          "2>" .
          "\0(ncolor)" .
          " " .
          "\0(stderr_text)" .
          $stderr_line );
}

sub start_terminal {
  if (DEBUG) { print ERRS "Enter start_terminal\n"; }
  my ($kernel, $heap, $object, $alias) = @_[KERNEL, HEAP, OBJECT, ARG0];
  
  $kernel->alias_set( $alias );
  $console = POE::Wheel::Curses->new( InputEvent => 'private_input');

  ### Set Colors used by Visterm
  _set_color( $object,  stderr_bullet => "bright white on red",
                        stderr_text   => "bright yellow on black",
                        ncolor        => "white on black",
                        statcolor     => "green on black", 
                        st_frames     => "bright cyan on blue",
                        st_values     => "bright white on blue", );


  ### Redirect STDERR into the terminal buffer.
  use Symbol qw(gensym);

  # Pipe STDERR to a readable handle.
  my $read_stderr = gensym();

  pipe($read_stderr, STDERR) or do
  { open STDERR, ">&=2";
    die "can't pipe STDERR: $!";
  };

  $heap->{stderr_reader} = POE::Wheel::ReadWrite->new
    ( Handle      => $read_stderr,
      Filter      => POE::Filter::Line->new(),
      Driver      => POE::Driver::SysRW->new(),
      InputEvent  => "got_stderr",
    );

}

### create a curses window
### TODO add error handling

sub create_window {
  if (DEBUG) { print ERRS "Enter create_window\n"; }
  my $self = shift;
  my %params = @_;
  my $use_title = 1 unless defined $params{Use_Title};
  my $use_status = 1 unless defined $params{Use_Status};
  my $new_window_id = CREATE_WINDOW_ID($self);
  my $window_name = $params{Window_Name} || $new_window_id;
  if (defined $new_window_id) {
    if (DEBUG) { print ERRS "new_window_id is defined: $new_window_id\n"; }
    if (!$self->[WINDOW]->{$new_window_id}) {
      $self->[WINDOW]->{$new_window_id} =
         { Buffer           => [ ],
           Buffer_Size      => $params{Buffer_Size} || 500,
           Command_History  => [ ],
           Cursor           => 0,
           Cursor_Save      => 0,
           Edit_Position    => 0,
           History_Position => -1,
           History_Size     => $params{History_Size} || 50,
           Input            => "",
           Input_Save       => "",
           Insert           => 1,
           Use_Title        => $use_title,
           Use_Status       => $use_status,
           Scrolled_Lines   => 0,
           Window_Id        => $new_window_id,
           Window_Name      => $window_name };

        my $winref = $self->[WINDOW]->{$new_window_id};

        # Set the newly created window as the current window
        $self->[CUR_WIN] = $new_window_id;

      $self->[WINDOW_REV]->{$window_name} = $new_window_id;

      # create the screen, statusbar, title, and entryline 
      # for this window instance

      if ($winref->{Use_Title}) {
        $winref->{Title_Start} = 0;
        $winref->{Title_Height} = 1;
        $winref->{Title} = $params{Title} || "";

        $winref->{Screen_Start} = $winref->{Title_Start} + 1;

        $winref->{Window_Title} =  newwin( $winref->{Title_Height}, 
                                    $COLS, 
                                    $winref->{Title_Start},
                                    0 );

        my $title = $winref->{Window_Title};

        $title->bkgd($self->[PALETTE]->{st_frames}->[PAL_PAIR]); 
        $title->erase();
        _refresh_title( $self, $new_window_id);
      }

      if ($winref->{Use_Status}) {
        $winref->{Status_Height} = $params{Status_Height} || 2;
        $winref->{Status_Start} = $LINES - $winref->{Status_Height} - 1;
        $winref->{Def_Status_Field} = [ ];
        $winref->{Screen_End} = $winref->{Status_Start} - 1;

        $winref->{Window_Status} = newwin( $winref->{Status_Height},
                                    $COLS,
                                    $winref->{Status_Start},
                                    0 );
        my $status = $winref->{Window_Status};
if (DEBUG) { print ERRS $status, " <-status in create_window\n"; }
        $status->bkgd($self->[PALETTE]->{st_frames}->[PAL_PAIR]); 
        $status->erase();
        $status->noutrefresh();

        $winref->{Status_Object} = Term::Visual::StatusBar->new();
        set_status_format( $self, $new_window_id, %{$params{Status}});
        $winref->{Status_Lines} = $winref->{Status_Object}->get();
        if (DEBUG) { print ERRS "passed set_status_format in create_window\n"; }
      }

      if ($winref->{Use_Title} && $winref->{Use_Status}) {
        $winref->{Screen_Height} = 
         $winref->{Screen_End} - $winref->{Screen_Start} + 1;
      }

      else {
        $winref->{Screen_Start} = 0 unless defined $winref->{Screen_Start};
        $winref->{Screen_End} = $LINES - 2 unless defined $winref->{Screen_End};
        $winref->{Screen_Height} = 
         $winref->{Screen_End} - $winref->{Screen_Start} + 1 
         unless defined $winref->{Screen_Height};
      }

      $winref->{Edit_Height} = 1;
      $winref->{Edit_Start} = $LINES - 1;

      $winref->{Buffer_Last} = $winref->{Buffer_Size} - 1;
      $winref->{Buffer_First} = $winref->{Screen_Height} - 1;
      $winref->{Buffer_Visible} = $winref->{Screen_Height} - 1;


      $winref->{Window_Edit} = newwin( $winref->{Edit_Height},
                                $COLS,
                                $winref->{Edit_Start},
                                0 );
      my $edit = $winref->{Window_Edit};
      $edit->scrollok(1);

      $winref->{Window_Screen} = newwin( $winref->{Screen_Height},
                                  $COLS,
                                  $winref->{Screen_Start},
                                  0 );
      my $screen = $winref->{Window_Screen};

      $screen->bkgd($self->[PALETTE]->{ncolor}->[PAL_PAIR]);
      $screen->erase();
      $screen->noutrefresh();

      $winref->{Buffer_Row} = $winref->{Buffer_Last};

      my $scrollback_a = ("# " x 39) . "12";
      my $scrollback_b = (" #" x 39) . "12";
      $winref->{Buffer} =
         [($scrollback_a, $scrollback_b) x ($winref->{Buffer_Size} / 2)];

      _refresh_edit($self, $new_window_id);

      # Fill the buffer with line numbers to test scrollback.

      if (TESTING) {
        my @lines = (1..$winref->{Buffer_Size});
        $lines[0] .= " *** FIRST LINE ***";
        $lines[-1] .= " *** LAST LINE ***";
        &print($self, $new_window_id, @lines);
      }
      else {
        &print($self, $new_window_id, "Geometry = $COLS columns and $LINES lines" );
      }

      # Flush updates.
      doupdate();


      return $new_window_id;
      
    }
    else { 
      if (DEBUG) { print ERRS "Window $params{Window_Name} already exists\n"; } 
      carp "Window $params{Window_Name} already exists"; 
    }
  }
  else { 
    if (DEBUG) { print ERRS "Window $params{Window_Name} couldn't be created\n"; }
    croak "Window $params{Window_Name} couldn't be created"; 
  }
}


### delete one or more windows  ##TODO add error handling
### $vt->delete_window($window_id);

### TODO update screen to the next or previous window. change in current window too
sub delete_window {
  if (DEBUG) { print ERRS "Enter delete_window\n"; }
  my $self = shift;
  for (@_) {
    my $name = get_window_name($self, $_);
    delete $self->[WINDOW]->{$_};
    delete $self->[WINDOW_REV]->{$name};
  }
}

### check if a window exists

sub validate_window {
  if (DEBUG) { print ERRS "Enter validate_window\n"; }
  my $self = shift;
  my $query = shift;
  if (DEBUG) { print ERRS "Validating: $query\n"; }
  if ($query =~ /^\d+$/ && defined $self->[WINDOW]->{$query}) { return 1; }
  elsif (defined $self->[WINDOW_REV]->{$query}) { return 1; }
  else { return 0; }
}

### return a windows palette or a specific colorname's description
### my %palette = $vt->get_palette(); # entire palette.
### my ($color_desc, $another_desc) = $vt->get_palette($colorname, $somecolor); # color desc.

sub get_palette {  
  my $self = shift;
  my @result;
  if ($#_ >= 0) { 
    for (@_) { push( @result, $self->[PALETTE]->{$_}->[PAL_DESC] ); }
    return @result;
  }
  else {
    for my $key (keys %{$self->[PALETTE]}) {
      push( @result, $key, $self->[PALETTE]->{$key}->[PAL_DESC]);
    }
    return @result;
  }

}

### set the palette for a window

sub set_palette {
  if (DEBUG) { print ERRS "Enter set_palette\n"; }
  my $self = shift;
  if (DEBUG) { print ERRS "palette needs an even number of parameters\n" if @_ & 1; } 
  croak "palette needs an even number of parameters" if @_ & 1;
  my %params = @_;
  _set_color($self, %params);
}

sub get_window_name {
  my $self = shift;
  my $id = shift;
  if ($id =~ /^\d+$/) {
    return $self->[WINDOW]->{$id}->{Window_Name};
  } 
  else { 
    if (DEBUG) { print ERRS "$id is not a Window ID\n"; }
    croak "$id is not a Window ID"; 
  }
}

sub get_window_id {
  my $self = shift;
  my $query = shift;
  my $validity = validate_window($self, $query);
  if ($validity) {
    return $self->[WINDOW_REV]->{$query};
  }
  else {
    if (DEBUG) { print ERRS "$query is not a Window Name\n"; }
    croak "$query is not a Window Name";
  }
}

### set the Title for a Window.

sub set_title {
  if (DEBUG) { print ERRS "Enter set_title\n"; }
  my $self = shift;
  my ($window_id, $title) = @_;
  my $validity = validate_window($self, $window_id);
  if ($validity) {
    $self->[WINDOW]->{$window_id}->{Title} = $title;
    if ($window_id == $self->[CUR_WIN]) {
      _refresh_title( $self, $window_id ); 
      doupdate();
    }
  }
  else {
    if (DEBUG) { print ERRS "Window $window_id is nonexistant\n"; }
    croak "Window $window_id is nonexistant";
  }
}

### get the Title for a Window.

sub get_title {
  my $self = shift;
  my $window_id = shift;
  my $validity = validate_window($self, $window_id);
  if ($validity) {
    return $self->[WINDOW]->{$window_id}->{Title};
  }
  else {
    if (DEBUG) { print ERRS "Window $window_id is nonexistant\n"; }
    croak "Window $window_id is nonexistant";
  }
}

### print lines to window
### a window_id must be given as the first argument.

sub print {
  if (DEBUG) { print ERRS "Enter print\n"; }
  my $self = shift;
  my $window_id = shift;
  my $validity = validate_window($self, $window_id);
  if ($validity) {
    my @lines = @_;
    my $winref = $self->[WINDOW]->{$window_id};

    foreach (@lines) {

      # Start a new line in the scrollback buffer.

      push @{$winref->{Buffer}}, "";
      $winref->{Scrolled_Lines}++;
      my $column = 1;

      # Build a scrollback line.  Stuff surrounded by \0() does not take
      # up screen space, so account for that while wrapping lines.

      my $last_color = "\0(ncolor)";
      while (length) {

        # Unprintable color codes.
        if (s/^(\0\([^\)]+\))//) {
          $winref->{Buffer}->[-1] .= $last_color = $1;
          next;
        }

        # Wordwrap visible stuff.
        if (s/^([^\0]+)//) {
          my @words = split /(\s+)/, $1;
          foreach my $word (@words) {
            unless (defined $word) {
              warn "undefined word";
              next;
            }

            if ($column + length($word) >= $COLS) {
              $winref->{Buffer}->[-1] .= "\0(ncolor)";
              push @{$winref->{Buffer}}, "$last_color    ";
              $winref->{Scrolled_Lines}++;
              $column = 5;
              next if $word =~ /^\s+$/;
            }

            $winref->{Buffer}->[-1] .= $word;
            $column += length($word);
          }
        }
      }  
    }

  # Keep the scrollback buffer a tidy length.
  splice(@{$winref->{Buffer}}, 0, @{$winref->{Buffer}} - $winref->{Buffer_Size})
    if @{$winref->{Buffer}} > $winref->{Buffer_Size};

  # Refresh the buffer when it's all done.
  _refresh_buffer($self, $window_id);  
  _refresh_edit($self, $window_id);    
  doupdate();         

  } # end brace of if ($validity) 
  else {
    if (DEBUG) { print ERRS "Can't print to nonexistant Window $window_id\n"; }
    croak "Can't print to nonexistant Window $window_id";
  }
}

### Register an input handler thing.

sub register_input {
  if (DEBUG) { print ERRS "Enter register_input\n"; }
  my ($kernel, $heap, $sender, $event) = @_[KERNEL, HEAP, SENDER, ARG0];

  # Remember the remote session and the event it wants to receive with
  # input.  This saves the sender's ID (instead of a reference)
  # because references mess with Perl's garbage collection.

  $heap->{input_session} = $sender->ID();
  $heap->{input_event}   = $event;

  # Increase the sender's reference count so the session stays alive
  # while the terminal is active.  We'll decrease the reference count
  # in _stop so it can go away when the terminal does.

  $kernel->refcount_increment( $sender->ID(), "terminal link" );
}

### Get input from the Curses thing.

sub got_curses_input {
  if (DEBUG) { print ERRS "Enter got_curses_input\n"; }
  my ($self, $kernel, $heap, $key) = @_[OBJECT, KERNEL, HEAP, ARG0];

  my $window_id = $self->[CUR_WIN];
  my $winref = $self->[WINDOW]->{$window_id};
  $key = uc(keyname($key)) if $key =~ /^\d{2,}$/;
  $key = uc(unctrl($key))  if $key lt " ";

  # If it's a meta key, save it.
  if ($key eq '^[') {
    $winref->{Prefix} .= $key;
    return;
  }

  # If there was a saved prefix, recall it.
  if ($winref->{Prefix}) {
    $key = $winref->{Prefix} . $key;
    $winref->{Prefix} = '';
  }

  ### Handle internal keystrokes here.  Page up, down, arrow keys, etc.

  # Beginning of line.
  if ($key eq '^A' or $key eq 'KEY_HOME') {
    if ($winref->{Cursor}) {
      $winref->{Cursor} = 0;
      _refresh_edit($self, $window_id); 
      doupdate();        
    }
    return;
  }

  # Back one character.
  if ($key eq 'KEY_LEFT') {
    if ($winref->{Cursor}) {
      $winref->{Cursor}--;
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }
  if (DEBUG) { print ERRS $key, "\n"; }
  # Switch Windows to the left  Shifted left arrow
  if ($key eq 'ð' or $key eq '^[KEY_LEFT') {
    $window_id--;
    change_window($self, $window_id );
    return;
  }

  # Switch Windows to the right  Shifted right arrow
  if ($key eq 'î' or $key eq '^[KEY_RIGHT') {
    $window_id++;
    change_window($self, $window_id );
    return;
  }

  # Interrupt.
  if ($key eq '^\\') {
    if (defined $heap->{input_session}) {
      $kernel->post( $heap->{input_session}, $heap->{input_event},
                     undef, 'interrupt'
                   );
      return;
    }

    # Ungraceful emergency exit.
    exit;
  }

  # Quit.
  if ($key eq '^\\') {
    if (defined $heap->{input_session}) {
      $kernel->post( $heap->{input_session}, $heap->{input_event},
                     undef, 'quit'
                   );
      return;
    }

    # Ungraceful emergency exit.
    exit;
  }

  # Delete a character.
  if ($key eq '^D' or $key eq 'KEY_DC') {
    if ($winref->{Cursor} < length($winref->{Input})) {
      substr($winref->{Input}, $winref->{Cursor}, 1) = '';
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # End of line.
  if ($key eq '^E' or $key eq 'KEY_LL') {
    if ($winref->{Cursor} < length($winref->{Input})) {
      $winref->{Cursor} = length($winref->{Input});
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Forward character.
  if ($key eq '^F' or $key eq 'KEY_RIGHT') {
    if ($winref->{Cursor} < length($winref->{Input})) {
      $winref->{Cursor}++;
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Backward delete character.
  if ($key eq '^H' or $key eq 'KEY_BACKSPACE') {
    if ($winref->{Cursor}) {
      $winref->{Cursor}--;
      substr($winref->{Input}, $winref->{Cursor}, 1) = '';
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Accept line.
  if ($key eq '^J' or $key eq '^M') {
    $kernel->post( $heap->{input_session}, $heap->{input_event},
                   $winref->{Input}, undef
                 );

    # And enter the line into the command history.
    command_history( $self, $window_id, 0 );  
    return;
  }

  # Kill to EOL.
  if ($key eq '^K') {
    if ($winref->{Cursor} < length($winref->{Input})) {
      substr($winref->{Input}, $winref->{Cursor}) = '';
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Refresh screen.
  if ($key eq '^L' or $key eq 'KEY_RESIZE') {

    # Refresh the title line.
    _refresh_title($self, $window_id);   

    # Refresh the status lines.
      _refresh_status( $self, $window_id);  

    # Refresh the buffer.
    _refresh_buffer($self, $window_id);  

    # Refresh the edit line.
    _refresh_edit($self, $window_id);

    # Flush updates.
    doupdate();

    return;
  }

  # Next in history.
  if ($key eq '^N'  ) {
    command_history( $self, $window_id, 2 ); 
    return;
  }

  # Previous in history.
  if ($key eq '^P' ) {
    command_history( $self, $window_id, 1 );
    return;
  }

  # Display input status.
  if ($key eq '^Q') {  
    &print( $self, $window_id,  # <- can I do this better?
               "\0(statcolor)******",
               "\0(statcolor)*** cursor is at $winref->{Cursor}",
               "\0(statcolor)*** input is: ``$winref->{Input}''",
               "\0(statcolor)*** scrolled lines: $winref->{Scrolled_Lines}",
               "\0(statcolor)*** screen height: " . $winref->{Screen_Height},
               "\0(statcolor)*** buffer row: $winref->{Buffer_Row}", 
               "\0(statcolor)*** scrollback height: " . scalar(@{$winref->{Buffer}}),
               "\0(statcolor)******"
             );
    return;
  }

  # Transpose characters.
  if ($key eq '^T') {
    if ($winref->{Cursor} > 0 and $winref->{Cursor} < length($winref->{Input})) {
      substr($winref->{Input}, $winref->{Cursor}-1, 2) =
        reverse substr($winref->{Input}, $winref->{Cursor}-1, 2);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Discard line.
  if ($key eq '^U') {
    if (length($winref->{Input})) {
      $winref->{Input} = '';
      $winref->{Cursor} = 0;
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Word rubout.
  if ($key eq '^W' or $key eq '^[^H') {
    if ($winref->{Cursor}) {
      substr($winref->{Input}, 0, $winref->{Cursor}) =~ s/(\S*\s*)$//;
      $winref->{Cursor} -= length($1);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # First in history.
  if ($key eq '^[<') {
    # TODO
    return;
  }

  # Last in history.
  if ($key eq '^[>') {
    # TODO
    return;
  }

  # Capitalize from cursor on.  Requires uc($key)
  if (uc($key) eq '^[C') {

    # If there's text to capitalize.
    if (substr($winref->{Input}, $winref->{Cursor}) =~ /^(\s*)(\S+)/) {

      # Track leading space, and uppercase word.
      my $space = $1; $space = '' unless defined $space;
      my $word  = ucfirst(lc($2));

      # Replace text with the uppercase version.
      substr( $winref->{Input},
              $winref->{Cursor} + length($space), length($word)
            ) = $word;

      $winref->{Cursor} += length($space . $word);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Uppercase from cursor on.  Requires uc($key)
  if (uc($key) eq '^[U') {

    # If there's text to uppercase.
    if (substr($winref->{Input}, $winref->{Cursor}) =~ /^(\s*)(\S+)/) {

      # Track leading space, and uppercase word.
      my $space = $1; $space = '' unless defined $space;
      my $word  = uc($2);

      # Replace text with the uppercase version.
      substr( $winref->{Input},
              $winref->{Cursor} + length($space), length($word)
            ) = $word;

      $winref->{Cursor} += length($space . $word);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Lowercase from cursor on.  Requires uc($key)
  if (uc($key) eq '^[L') {

    # If there's text to uppercase.
    if (substr($winref->{Input}, $winref->{Cursor}) =~ /^(\s*)(\S+)/) {

      # Track leading space, and uppercase word.
      my $space = $1; $space = '' unless defined $space;
      my $word  = lc($2);

      # Replace text with the uppercase version.
      substr( $winref->{Input},
              $winref->{Cursor} + length($space), length($word)
            ) = $word;

      $winref->{Cursor} += length($space . $word);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Forward one word.  Requires uc($key)
  if (uc($key) eq '^[F') {
    if (substr($winref->{Input}, $winref->{Cursor}) =~ /^(\s*\S+)/) {
      $winref->{Cursor} += length($1);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Backward one word.  This needs uc($key).
  if (uc($key) eq '^[B') {
    if (substr($winref->{Input}, 0, $winref->{Cursor}) =~ /(\S+\s*)$/) {
      $winref->{Cursor} -= length($1);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Delete a word forward.  This needs uc($key).
  if (uc($key) eq '^[D') {
    if ($winref->{Cursor} < length($winref->{Input})) {
      substr($winref->{Input}, $winref->{Cursor}) =~ s/^(\s*\S*\s*)//;
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Transpose words.  This needs uc($key).
  if (uc($key) eq '^[T') {
    my ($previous, $left, $space, $right, $rest);

    if (substr($winref->{Input}, $winref->{Cursor}, 1) =~ /\s/) {
      my ($left_space, $right_space);
      ($previous, $left, $left_space) =
        ( substr($winref->{Input}, 0, $winref->{Cursor}) =~ /^(.*?)(\S+)(\s*)$/
        );
      ($right_space, $right, $rest) =
        ( substr($winref->{Input}, $winref->{Cursor}) =~ /^(\s+)(\S+)(.*)$/
        );
      $space = $left_space . $right_space;
    }
    elsif ( substr($winref->{Input}, 0, $winref->{Cursor}) =~
            /^(.*?)(\S+)(\s+)(\S*)$/
          ) {
      ($previous, $left, $space, $right) = ($1, $2, $3, $4);
      if (substr($winref->{Input}, $winref->{Cursor}) =~ /^(\S*)(.*)$/) {
        $right .= $1 if defined $1;
        $rest = $2;
      }
    }
    elsif (substr($winref->{Input}, $winref->{Cursor}) =~ /^(\S+)(\s+)(\S+)(.*)$/
          ) {
      ($left, $space, $right, $rest) = ($1, $2, $3, $4);
      if ( substr($winref->{Input}, 0, $winref->{Cursor}) =~ /^(.*?)(\S+)$/ ) {
        $previous = $1;
        $left = $2 . $left;
      }
    }
    else {
      return;
    }

    $previous = '' unless defined $previous;
    $rest     = '' unless defined $rest;

    $winref->{Input}  = $previous . $right . $space . $left . $rest;
    $winref->{Cursor} = length($previous. $left . $space . $right);

    _refresh_edit($self, $window_id);
    doupdate();
    return;
  }

  # Toggle insert mode.
  if ($key eq 'KEY_IC') {
    $winref->{Insert} = !$winref->{Insert};
    return;
  }

  # Scroll back a page.  
  if ($key eq 'KEY_PPAGE') {
    if ($winref->{Buffer_Row} > $winref->{Buffer_First}) {
      $winref->{Buffer_Row} -= $winref->{Screen_Height};
      if ($winref->{Buffer_Row} < $winref->{Buffer_First}) {
        $winref->{Buffer_Row} = $winref->{Buffer_First}
      } 
      _refresh_buffer($self, $window_id);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Scroll forward a page. 
  if ($key eq 'KEY_NPAGE') {
    if ($winref->{Buffer_Row} < $winref->{Buffer_Last}) {
      $winref->{Buffer_Row} += $winref->{Screen_Height};
      if ($winref->{Buffer_Row} > $winref->{Buffer_Last}) {
        $winref->{Buffer_Row} = $winref->{Buffer_Last};
      }
      _refresh_buffer($self, $window_id);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Scroll back a line. 
  if ($key eq 'KEY_UP') {
    if ($winref->{Buffer_Row} > $winref->{Buffer_First}) {
      $winref->{Buffer_Row}--;
      _refresh_buffer($self, $window_id);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  # Scroll forward a line. 
  if ($key eq 'KEY_DOWN') {
    if ($winref->{Buffer_Row} < $winref->{Buffer_Last}) {
      $winref->{Buffer_Row}++;
      _refresh_buffer($self, $window_id);
      _refresh_edit($self, $window_id);
      doupdate();
    }
    return;
  }

  ### Not an internal keystroke.  Add it to the input buffer.
  # double check if this is needed...
  $key = chr(ord($1)-64) if $key =~ /^\^([@-_BC])$/;

  # Inserting or overwriting in the middle of the input.
  if ($winref->{Cursor} < length($winref->{Input})) {
    if ($winref->{Insert}) {
      substr($winref->{Input}, $winref->{Cursor}, 0) = $key;
    }
    else {
      substr($winref->{Input}, $winref->{Cursor}, length($key)) = $key;
    }
  }

  # Appending.
  else {
    $winref->{Input} .= $key;
  }

  $winref->{Cursor} += length($key);
  _refresh_edit($self, $window_id);
  doupdate();
  return;
}

my %ctrl_to_visible;
BEGIN {
  for (0..31) {
    $ctrl_to_visible{chr($_)} = chr($_+64);
  }
}

### Common thing.  Refresh the buffer on the screen.
##  Pass in $self and a window_id 

sub _refresh_buffer {
  if (DEBUG) { print ERRS "Enter _refresh_buffer\n"; }
  my $self = shift;
  my $window_id = shift;
  my $winref = $self->[WINDOW]->{$window_id};
  my $screen = $winref->{Window_Screen};

  if ($window_id != $self->[CUR_WIN]) { return; }
  # Adjust the buffer row to compensate for any scrolling we encounter
  # while in scrollback.

  if ($winref->{Buffer_Row} < $winref->{Buffer_Last}) {
    $winref->{Buffer_Row} -= $winref->{Scrolled_Lines};
  }

  # Don't scroll up past the start of the buffer.

  if ($winref->{Buffer_Row} < $winref->{Buffer_First}) {
    $winref->{Buffer_Row} = $winref->{Buffer_First};
  }

  # Don't scroll down past the bottom of the buffer.

  if ($winref->{Buffer_Row} > $winref->{Buffer_Last}) {
    $winref->{Buffer_Row} = $winref->{Buffer_Last};
  }

  # Now splat the last N lines onto the screen.

  $screen->erase();
  $screen->noutrefresh();

  $winref->{Scrolled_Lines} = 0;

  my $screen_y = 0;
  my $buffer_y = $winref->{Buffer_Row} - $winref->{Buffer_Visible};
  while ($screen_y < $winref->{Screen_Height}) {
    $screen->move($screen_y, 0);
    $screen->clrtoeol();
    $screen->noutrefresh();

    next if $buffer_y < 0;
    next if $buffer_y > $winref->{Buffer_Last};

    my $line = $winref->{Buffer}->[$buffer_y]; # does this work?
    my $column = 1;
    while (length $line) {
      if ($line =~ s/^\0\(blink_(on|off)\)//) {
         if ($1 eq 'on') { $screen->attron(A_BLINK); }
         if ($1 eq 'off') { $screen->attroff(A_BLINK); }
         $screen->noutrefresh();
      }

      if ($line =~ s/^\0\(bold_(on|off)\)//) {
         if ($1 eq 'on') { $screen->attron(A_BOLD); }
         if ($1 eq 'off') { $screen->attroff(A_BOLD); }
         $screen->noutrefresh();
      }

      if ($line =~ s/^\0\(underline_(on|off)\)//) {
         if ($1 eq 'on') { $screen->attron(A_UNDERLINE); }
         if ($1 eq 'off') { $screen->attroff(A_UNDERLINE); }
         $screen->noutrefresh();
      }

      if ($line =~ s/^ \0 \( ([^\)]+) \) //x) {
        $screen->attrset($self->[PALETTE]->{$1}->[PAL_PAIR]); 
        $screen->noutrefresh();
      }
      if ($line =~ s/^([^\0]+)//x) {

        # TODO: This needs to be revised so it cuts off the last word,
        # not omits it entirely.

        next if $column >= $COLS;
        if ($column + length($1) > $COLS) {
          my $word = $1;
          substr($word, ($column + length($1)) - $COLS - 1) = '';
          $screen->addstr($word);
        }
        else {
          $screen->addstr($1);
        }
        $column += length($1);
        $screen->noutrefresh();
      }
    }

    $screen->attrset($self->[PALETTE]->{ncolor}->[PAL_PAIR]); 
    $screen->noutrefresh();
    $screen->clrtoeol();
    $screen->noutrefresh();
  }
  continue {
    $screen_y++;
    $buffer_y++;
  }
}

# Internal function to set the color palette for a window.

sub _set_color {
  if (DEBUG) { print ERRS "Enter _set_color\n"; }
  my $self= shift;
#  my $window_id = shift;
#  my $winref = $self->[WINDOW]->{$window_id};
  my %params = @_;

  my %color_table =
   ( bk      => COLOR_BLACK,    black   => COLOR_BLACK,
     bl      => COLOR_BLUE,     blue    => COLOR_BLUE,
     br      => COLOR_YELLOW,   brown   => COLOR_YELLOW,
     fu      => COLOR_MAGENTA,  fuschia => COLOR_MAGENTA,
     cy      => COLOR_CYAN,     cyan    => COLOR_CYAN,
     gr      => COLOR_GREEN,    green   => COLOR_GREEN,
     ma      => COLOR_MAGENTA,  magenta => COLOR_MAGENTA,
     re      => COLOR_RED,      red     => COLOR_RED,
     wh      => COLOR_WHITE,    white   => COLOR_WHITE,
     ye      => COLOR_YELLOW,   yellow  => COLOR_YELLOW,
   );

  my %attribute_table =
   ( al         => A_ALTCHARSET,
     alt        => A_ALTCHARSET,
     alternate  => A_ALTCHARSET,
     blink      => A_BLINK,
     blinking   => A_BLINK,
     bo         => A_BOLD,
     bold       => A_BOLD,
     bright     => A_BOLD,
     dim        => A_DIM,
     fl         => A_BLINK,
     flash      => A_BLINK,
     flashing   => A_BLINK,
     hi         => A_BOLD,
     in         => A_INVIS,
     inverse    => A_REVERSE,
     inverted   => A_REVERSE,
     invisible  => A_INVIS,
     inviso     => A_INVIS,
     lo         => A_DIM,
     low        => A_DIM,
     no         => A_NORMAL,
     norm       => A_NORMAL,
     normal     => A_NORMAL,
     pr         => A_PROTECT,
     prot       => A_PROTECT,
     protected  => A_PROTECT,
     reverse    => A_REVERSE,
     rv         => A_REVERSE,
     st         => A_STANDOUT,
     stand      => A_STANDOUT,
     standout   => A_STANDOUT,
     un         => A_UNDERLINE,
     under      => A_UNDERLINE,
     underline  => A_UNDERLINE,
     underlined => A_UNDERLINE,
     underscore => A_UNDERLINE,
   );


  for my $color_name (keys %params) {

    my $description = $params{$color_name};
    my $foreground = 0;
    my $background = 0;
    my $attributes = 0;

    # Which is an alias to foreground or background depending on what
    # state we're in.
    my $which = \$foreground;

    # Clean up the color description.
    $description =~ s/^\s+//;
    $description =~ s/\s+$//;
    $description = lc($description);

    # Parse the description.
    foreach my $word (split /\s+/, $description) {

      # The word "on" means we're switching to background.
      if ($word eq 'on') {
        $which = \$background;
        next;
      }

      # If it's a color name, combine its value with the foreground or
      # background, whichever is currently selected.
      if (exists $color_table{$word}) {
        $$which |= $color_table{$word};
        next;
      }

      # If it's an attribute, it goes with attributes.
      if (exists $attribute_table{$word}) {
        $attributes |= $attribute_table{$word};
        next;
      }

      # Otherwise it's an error.
      if (DEBUG) { print ERRS "unknown color keyword \"$word\"\n"; }
      croak "unknown color keyword \"$word\"";
    }

    # If the palette already has that color, redefine it.
    if (exists $self->[PALETTE]->{$color_name}) {
      my $old_color_number = $self->[PALETTE]->{$color_name}->[PAL_NUMBER];
      init_pair($old_color_number, $foreground, $background);
      $self->[PALETTE]->{$color_name}->[PAL_PAIR] =
        COLOR_PAIR($old_color_number) | $attributes;
    }
    else {
      my $new_color_number = ++$self->[PAL_COL_SEQ];
      init_pair($new_color_number, $foreground, $background);
      $self->[PALETTE]->{$color_name} =
        [ COLOR_PAIR($new_color_number) | $attributes,  # PAL_PAIR
          $new_color_number,                            # PAL_NUMBER
          $description,                                 # PAL_DESC
        ];
    }
  }
}

### The terminal stopped.  Remove the reference count for the remote
### session.

sub terminal_stopped {
  if (DEBUG) { print ERRS "Enter terminal_stopped\n"; }
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  if (defined $heap->{input_session}) {
    $kernel->refcount_decrement( $heap->{input_session}, "terminal link" );
    delete $heap->{input_session};
  }
}

sub change_window {
  if (DEBUG) { print ERRS "change_window called\n"; }
  my $self = shift;
  my $window_id = shift;
  my @list = sort {$a <=> $b} keys %{$self->[WINDOW]};

  if (@list) {
    if ($window_id == -1) {
       $window_id = $list[$#list];
    }
    elsif ($window_id > $list[$#list]) {
      $window_id = 0;
    }
  }

  my $validity = validate_window($self, $window_id);
  if ($validity) {
    $self->[CUR_WIN] = $window_id;
    update_window( $self, $window_id );
  }
}

sub update_window {
  my $self = shift;
  my $window_id = shift;

  _refresh_title( $self, $window_id );
  _refresh_buffer( $self, $window_id );
  _refresh_status( $self, $window_id ); 
  _refresh_edit( $self, $window_id );
  doupdate();
}

sub _refresh_title {
  if (DEBUG) { print ERRS "Enter _refresh_title\n"; }
  my ($self, $window_id) = @_;
  my $winref = $self->[WINDOW]->{$window_id};
  my $title = $winref->{Window_Title};

  if ($window_id != $self->[CUR_WIN]) { return; }

  $title->move(TITLE_LINE, TITLE_COL);
  $title->attrset($self->[PALETTE]->{st_values}->[PAL_PAIR]); 
  $title->noutrefresh();
  $title->addstr($winref->{Title}) unless !$winref->{Title};
  $title->noutrefresh();
  $title->clrtoeol();
  $title->noutrefresh();
  doupdate();
}

sub _refresh_edit {
  if (DEBUG) { print ERRS "Enter _refresh_edit\n"; }
  my $self = shift;
  my $window_id = shift;
  my $winref = $self->[WINDOW]->{$window_id};
  my $edit = $winref->{Window_Edit};
  my $visible_input = $winref->{Input};

  # If the cursor is after the last visible edit position, scroll the
  # edit window left so the cursor is back on-screen.

  if ($winref->{Cursor} - $winref->{Edit_Position} >= $COLS) {
    $winref->{Edit_Position} = $winref->{Cursor} - $COLS + 1;
  }

  # If the cursor is moving left of the middle of the screen, scroll
  # things to the right so that both sides of the cursor may be seen.

  elsif ($winref->{Cursor} - $winref->{Edit_Position} < ($COLS >> 1)) {
    $winref->{Edit_Position} = $winref->{Cursor} - ($COLS >> 1);
    $winref->{Edit_Position} = 0 if $winref->{Edit_Position} < 0;
  }

  # If the cursor is moving right of the middle of the screen, scroll
  # things to the left so that both sides of the cursor may be seen.

  elsif ( $winref->{Cursor} <= length($winref->{Input}) - ($COLS >> 1) + 1 ){
    $winref->{Edit_Position} = $winref->{Cursor} - ($COLS >> 1);
  }

  # Condition $visible_input so it really is.
  $visible_input = substr($visible_input, $winref->{Edit_Position}, $COLS-1);

  $edit->attron(A_NORMAL);
  $edit->erase();
  $edit->noutrefresh();

  while (length($visible_input)) {
    if ($visible_input =~ /^[\x00-\x1f]/) {
      $edit->attron(A_UNDERLINE);
      while ($visible_input =~ s/^([\x00-\x1f])//) {
        $edit->addstr($ctrl_to_visible{$1});
      }
    }
    if ($visible_input =~ s/^([^\x00-\x1f]+)//) {
      $edit->attroff(A_UNDERLINE);
      $edit->addstr($1);
    }
  }

  $edit->noutrefresh();
  $edit->move( 0, $winref->{Cursor} - $winref->{Edit_Position} );
  $edit->noutrefresh();
}

### Set or call command history lines.

sub command_history {
  if (DEBUG) { print ERRS "Enter command_history\n"; }
  my $self = shift;
  my $window_id = shift;
  my $flag = shift;
  my $winref = $self->[WINDOW]->{$window_id};

  if ($flag == 0) { #add to command history

    # Add to the command history.  Discard the oldest item if the
    # history size is bigger than our maximum length.

    unshift(@{$winref->{Command_History}}, $winref->{Input});
    pop(@{$winref->{Command_History}}) if @{$winref->{Command_History}} > $winref->{History_Size};

    # Reset the input, saved input, and history position.  Repaint the
    # edit box.

    $winref->{Input_Save} = $winref->{Input} = "";
    $winref->{Cursor_Save} = $winref->{Cursor} = 0;
    $winref->{History_Position} = -1;

    _refresh_edit($self, $window_id);
    doupdate();

    return;
  }

  if ($flag == 1) { # get last history 'KEY_UP'

    # At <0 command history, we save the input and move into the
    # command history.  The saved input will be used in case we come
    # back.

    if ($winref->{History_Position} < 0) {
      if (@{$winref->{Command_History}}) {
        $winref->{Input_Save} = $winref->{Input};
        $winref->{Cursor_Save} = $winref->{Cursor};
        $winref->{Input} = 
          $winref->{Command_History}->[++$winref->{History_Position}];
        $winref->{Cursor} = length($winref->{Input});

        _refresh_edit($self, $window_id);
        doupdate();
      }
    }

    # If we're not at the end of the command history, then we go
    # farther back.

    elsif ($winref->{History_Position} < @{$winref->{Command_History}} - 1) {
      $winref->{Input} = $winref->{Command_History}->[++$winref->{History_Position}];
      $winref->{Cursor} = length($winref->{Input});

      _refresh_edit($self, $window_id);
      doupdate();
    }

    return;
  }

  if ($flag == 2) { # get next history 'KEY_DOWN'

    # At 0th command history.  Switch to saved input.
    unless ($winref->{History_Position}) {
      $winref->{Input} = $winref->{Input_Save};
      $winref->{Cursor} = $winref->{Cursor_Save};
      $winref->{History_Position}--;
      _refresh_edit($self, $window_id);
      doupdate();
    }

    # At >0 command history.  Move towards 0.
    elsif ($winref->{History_Position} > 0) {
      $winref->{Input} = $winref->{Command_History}->[--$winref->{History_Position}];
      $winref->{Cursor} = length($winref->{Input});
      _refresh_edit($self, $window_id);
      doupdate();
    }

    return;
  }

  warn "unknown flag $flag";
}

sub set_status_field {
  if (DEBUG) { print ERRS "Enter set_status_field\n"; }
  my $self = shift;
  my $window_id = shift;
  my $validity = validate_window($self, $window_id);
  if ($validity) {
    my $winref = $self->[WINDOW]->{$window_id};
    my $status_obj = $winref->{Status_Object};
    $winref->{Status_Lines} = $status_obj->set(@_);
      _refresh_status($self, $window_id);
      _refresh_edit($self, $window_id);
      doupdate();

  }
}

sub set_status_format {
  if (DEBUG) { print ERRS "Enter set_status_format\n"; }
  my $self = shift;
  my $window_id = shift;
  my %status_formats = @_;
  if (DEBUG) { print ERRS %status_formats, " <-status_formats\n"; }
  my $validity = validate_window($self, $window_id);
  if ($validity) {
    my $winref = $self->[WINDOW]->{$window_id};
    my $status_obj = $winref->{Status_Object};
  if (DEBUG) { print ERRS "calling status_obj->set_format\n"; }
    $status_obj->set_format(%status_formats);
  if (DEBUG) { print ERRS "calling status_obj->get\n"; }
  $winref->{Status_Lines} = $status_obj->get();
if (DEBUG) { print ERRS "calling refresh_status\n"; }
    # Update the status line.
    _refresh_status( $self, $window_id );
if (DEBUG) { print ERRS "returned from refresh_status\n"; }
    doupdate();
  }
}

sub _refresh_status {
  if (DEBUG) { print ERRS "Enter _refresh_status\n"; }
  my ($self, $window_id) = (shift, shift);

  if ($window_id != $self->[CUR_WIN]) { return; }

  my ($row, $value);
  my $winref = $self->[WINDOW]->{$window_id};
  my $status = $winref->{Window_Status};
  my @status_lines = @{$winref->{Status_Lines}};
  while (@status_lines) {
    if (DEBUG) { print ERRS "in main while loop of refresh_status\n"; }
    $row = shift @status_lines;
    $value = shift @status_lines;
if (DEBUG) { print ERRS "$row <-row value-> $value\n"; }
if (DEBUG) { print ERRS $status, "<-status ref\n"; }
    $status->move( $row, 0 );

    # Parse the value.  Stuff surrounded by ^C is considered color
    # names.  This interferes with epic/mirc colors.

    while (defined $value and length $value) {
      if (DEBUG) { print ERRS "while defined value and length value in refresh_status\n"; }
      if ($value =~ s/^\0\(([^\)]+)\)//) {
        if (DEBUG) { print ERRS "value matched", '^\0\(([^\)]+)\)', "\n"; }
        $status->attrset($self->[PALETTE]->{$1}->[PAL_PAIR]);
        $status->noutrefresh();
      }
      if ($value =~ s/^([^\0]+)//) {
        if (DEBUG) { print ERRS "value matched", '^([^\0]+)', "\n"; }
        $status->addstr($1);
        $status->noutrefresh();
      }
    }
  }

  # Clear to the end of the line, and refresh the status bar.
  $status->attrset($self->[PALETTE]->{st_frames}->[PAL_PAIR]); 
  $status->noutrefresh();
  $status->clrtoeol();
  $status->noutrefresh();

}



sub set_errlevel {}
sub get_errlevel {}

sub error {}

sub shutdown {}

1;

__END__

=head1 NAME

Term::Visual - split-terminal user interface

=head1 SYNOPSIS

  #!/usr/bin/perl -w
  use strict;

  use Term::Visual;

  my $vt = Term::Visual->new(    Alias => "interface",
                              Errlevel => 0 );

  $vt->set_palette( mycolor   => "magenta on black",
                    thiscolor => "green on black" );

  my $window_id = $vt->create_window(
        Window_Name  => "foo",

        Status       => { 0 =>
                           { format => "template for status line 1",
                             fields => [qw( foo bar )] },
                          1 =>
                           { format => "template for status line 2",
                             fields => [ qw( biz baz ) ] },
                        },

        Buffer_Size  => 1000,
        History_Size => 50,
 
        Use_Title    => 0, # Don't use a titlebar 
        Use_Status   => 0, # Don't use a statusbar

        Title        => "Title of foo"  );
                    
  $vt->set_status_field( $window_id, bar => $value );

  $vt->print( $window_id, "my Window ID is $window_id" );

  $vt->shutdown; # not implemented yet.

  for now use delete_window

  $vt->delete_window( $window_id );

=head1 PUBLIC METHODS

Term::Visual->method();

=over 2

=item new

Create and initialize a new instance of Term::Visual.

  my $vt = Term::Visual->new(    Alias => "interface",
                              Errlevel => 0 );

Alias is a session alias for POE.

Errlevel not implemented yet.

Errlevel sets Term::Visual's error level.

=item create_window

  my $window_id = $vt->create_window( ... );

Set the window's name

  Window_Name => "foo"

Set the Statusbar's format

  Status => { 0 => # first statusline
               { format => "\0(st_frames)" .
                           " [" .
                           "\0(st_values)" .
                           "%8.8s" .
                           "\0(st_frames)" .
                           "] " .
                           "\0(st_values)" .
                           "%s",
                 fields => [qw( time name )] },
              1 => # second statusline
               { format => "foo %s bar %s",
                 fields => [qw( foo bar )] },
            } 

Set the size of the scrollback buffer

  Buffer_Size => 1000

Set the command history size

  History_Size => 50

Set the title of the window

  Title => "This is the Titlebar"

Don't use Term::Visual's Titlebar.

  Use_Title => 0

Don't use Term::Visual's StatusBar.

  Use_Status => 0

No need to declare Use_Status or Use_Title if you want to use
the Statusbar or Titlebar.

=item print

Prints lines of text to the main screen of a window

  $vt->print( $window_id, "this is a string" );

  my @array = qw(foo bar biz baz);
  $vt->print( $window_id, @array );

=item current_window

  my $current_window = $vt->current_window;

  $vt->print( $current_window, "current window is $current_window" );

=item get_window_name

  my $window_name = $vt->get_window_name( $window_id );

=item get_window_id

  my $window_id = $vt->get_window_id( $window_name );

=item delete_window

  $vt->delete_window($window_id);

or

  $vt->delete_window(@window_ids);

=item validate_window

  my $validity = $vt->validate_window( $window_id );

or 

  my $validity = $vt->validate_window( $window_name );

  if ($validity) { do stuff };

=item get_palette

Return color palette or a specific colorname's description.

  my %palette = $vt->get_palette();

  my $color_desc = $vt->get_palette($colorname);

  my ($foo, $bar) = $vt->get_palette($biz, $baz);

=item set_palette

Set the color palette or specific colorname's value.

  $vt->set_palette( color_name => "color on color" );

  $vt->set_palette( color_name => "color on color",
                    another    => "color on color" );

  NOTE: (ncolor, st_values, st_frames, stderr_text, stderr_bullet, statcolor)
         are set and used by Term::Visual internally.
         It is safe to redifine there values.

=item set_title

  $vt->set_title( $window_id, "This is the new Title" );

=item get_title

  my $title = $vt->get_title( $window_id );

=item change_window

Switch between windows

  $vt->change_window( $window_id );

  $vt->change_window( 0 );

  ...

  $vt->change_window( 1 );

=item set_status_format

  $vt->set_status_format( $window_id,
            0 => { format => "template for status line 1",
                   field  => [ qw( foo bar ) ] },
            1 => { format => "template for status line 2",
                   field  => [ qw( biz baz ) ] }, );

=item set_status_field

  $vt->set_status_field( $window_id, field => "value" );

  $vt->set_status_field( $window_id, foo => "bar", biz => "baz" );

=back

=head1 Internal Keystrokes

=over 2

=item Ctrl A or KEY_HOME

Move to BOL.

=item KEY_LEFT

Back one character.

=item Alt P or Esc KEY_LEFT

Switch Windows decrementaly.

=item Alt N or Esc KEY_RIGHT

Switch Windows incrementaly.

=item Alt K or KEY_END

Not implemented yet.

Kill a Window.

=item Ctrl \

Kill Term::Visual.

=item Ctrl D or KEY_DC

Delete a character.

=item Ctrl E or KEY_LL

Move to EOL.

=item Ctrl F or KEY_RIGHT

Forward a character.

=item Ctrl H or KEY_BACKSPACE

Backward delete character.

=item Ctrl J or Ctrl M 'Return'

Accept a line.

=item Ctrl K

Kill to EOL.

=item Ctrl L or KEY_RESIZE

Refresh screen.

=item Ctrl N

Next in history.

=item Ctrl P

Previous in history.

=item Ctrl Q

Display input status.

=item Ctrl T

Transpose characters.

=item Ctrl U

Discard line.

=item Ctrl W

Word rubout.

=item Esc C

Capitalize word to right of cursor.

=item Esc U

Uppercase WORD.

=item Esc L

Lowercase word.

=item Esc F

Forward one word.

=item Esc B

Backward one word.

=item Esc D

Delete a word forward.

=item Esc T

Transpose words.

=item KEY_IC 'Insert'

Toggle Insert mode.

=item KEY_PPAGE 'Page Down'

Scroll down a page.

=item KEY_NPAGE 'Page Up'

Scroll up a page.

=item KEY_UP

Scroll up a line.

=item KEY_DOWN

Scroll down a line.

=back    

=head1 Author

=over 2

=item Charles Ayres


Except where otherwise noted, 
Term::Visual is Copyright 2002, 2003 Charles Ayres. All rights reserved.
Term::Visual is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

Questions and Comments can be sent to lunartear+visterm@ambientheory.com

=back

=head1 Acknowledgments

=over 2

=item Rocco Caputo

A Big thanks to Rocco Caputo. 

Rocco has contributed to the development
of Term::Visual In many ways.

Rocco Caputo <troc+visterm@pobox.com>

=back

Thank you!

=cut
