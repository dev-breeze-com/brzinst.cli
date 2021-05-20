#!//usr/bin/env perl

use strict;
use warnings;

use POSIX qw(:signal_h :errno_h :sys_wait_h);

use Data::Dumper qw(Dumper);

my %GLOBALSEQ;
my @ORDERING;
my %METADATA;
my %SELECTED;
my %LOCALES;
my $ACTIONS;

my $SECTION = undef;
my $EXEC_MODE = undef;
my $CUREVAL = 1;
my $RUNNING = 1;
my $MAXSTEPS = 0;
my $STEP = 0;

my $NCOLS = `tput cols`; chomp $NCOLS;
my $NLINES = `tput lines`; chomp $NLINES;

sub goto_step {
    my $step = shift;

    $STEP = $step < 0 ? 0 : ( $step > $MAXSTEPS ? $MAXSTEPS : $step);
#   print ">>> STEP[", $STEP, "]\n";

    $SECTION = $ORDERING[$STEP];
#   print ">>> SECTION[", $SECTION, "]\n";

    $EXEC_MODE = $ACTIONS->{ "ordering" }->{ $SECTION };
};

sub goto_action {
    my $step = shift;
    my $incr = 0;

    foreach (@ORDERING) {
#        print "goto_action: $step = ", $_, "\n";
        if ($_ eq $step) {
            goto_step( $incr );
            return 1;
        }
        $incr++;
    }
    return 0;
};

sub goto_prev {
    my $step = $STEP;
    goto_step( $step ? --$step : $step );
};

sub goto_next {
    my $step = $STEP;
    goto_step( $step ? ++$step : $step );
};

sub goto_home {
    goto_action( $SECTION = "homepage" );
};

sub replace_html_tags {

    my $text = shift;
    my $tagmode = shift;
    my $indent = "    ";

    if ($text) {
        my @tags = $text =~ m/(<[\/]?[^>]+>)/g;

        foreach (@tags) {
            my $tag = $_;

             if ($tag =~ m/<(br|ul)[\/]?[ >]/) {
                if ($tagmode) {
                    $text =~ s/${tag}/\n$indent/g;
                } else {
                    $text =~ s/${tag}/\n/g;
                }
            }
            elsif ($tag =~ m/<li[> ]/) {
                $text =~ s/${tag}/\n$indent/;
            }
            elsif ($tag =~ m/<h[012345][ >]/) {
                $text =~ s/${tag}/[4m[1m/;
            }
            elsif ($tag =~ m/<u[ >]/) {
                $text =~ s/${tag}/[4m/;
            }
            elsif ($tag =~ m/<a[ ].*(apply|continue)[^>]*>/) {
                $text =~ s/${tag}/[4m[1m/;
            }
            elsif ($tag =~ m/<img[ ].*apply[^>]*>/) {
                $text =~ s/${tag}/Apply/;
            }
            elsif ($tag =~ m/<img[ ].*next[^>]*>/) {
                $text =~ s/${tag}/Next/;
            }
            elsif ($tag =~ m/<b[ >]/) {
                $text =~ s/${tag}/[1m/;
            }
            elsif ($tag =~ m/<big[ >]/) {
                $text =~ s/${tag}/[3m/;
            }
            elsif ($tag =~ m/<(span|font) color=.*red/) {
                $text =~ s/${tag}/[0;0;31m/;
            }
            elsif ($tag =~ m/<(span|font) color=.*yellow/) {
                $text =~ s/${tag}/[0;0;32m/;
            }
            elsif ($tag =~ m/<(span|font) color=.*green/) {
                $text =~ s/${tag}/[0;0;33m/;
            }
            elsif ($tag =~ m/<(span|font) color=.*blue/) {
                $text =~ s/${tag}/[0;0;35m/;
            }
            elsif ($tag =~ m/<(span|font) color=.*33FB01/) {
                $text =~ s/${tag}/[0;1;33m/;
            }
            elsif ($tag =~ m/<(span|font) color=.*cyan/) {
                $text =~ s/${tag}/[0;0;36m/;
            }
            elsif ($tag =~ m/<\/p[ >]/) {
                $text =~ s/${tag}/\n\n/g;
            }
            elsif ($tag =~ m/<\/ul[ >]/) {
                $text =~ s/${tag}/\n\n/g;
            }
            elsif ($tag =~ m/<\/h[012345][ >]/) {
                $text =~ s/${tag}/[0m\n\n/;
            }
            elsif ($tag =~ m/<\/(big|a|b|u|font|span)[ >]/) {
                $text =~ s/${tag}/[0m/;
            }
            elsif ($tag =~ m/<[\/]?(p|li|html|body)[ >]/) {
                $text =~ s/${tag}//g;
            }
            elsif ($tag =~ m/<p /) {
                #my $repl = $HTMLTAGS{ $tag };
        #$text =~ s/${tag}/$repl/;
            }
        }
    }

    $text =~ s/\\n/\n/;
    $text = "${text}[0m";

    return $text;
};

sub replace_tags {

    my $text = shift;
    my $evalmode = shift;
    my %hmeta = @_;

    if ($text) {
        my @tags = $text =~ m/\$([\w_-]+)/g;

        foreach (@tags) {
            my $tag = $_;
            my $repl = $ENV{ "${tag}" };

            if ($evalmode) {
                $text =~ s/\$${tag}/\"$repl\" /;
            } else {
                $text =~ s/\$${tag}/$repl/;
            }
        }

        @tags = $text =~ m/\%([^\%]+)\%/g;

        foreach (@tags) {
            my $tag = $_;
            my $repl = %hmeta ? $hmeta{ $tag } : $METADATA{ $tag };

            $repl = $repl ? $repl : $METADATA{ $tag };

            if ($evalmode) {
                $text =~ s/\%${tag}\%/\"$repl\" /;
            } else {
                $text =~ s/\%${tag}\%/$repl/;
            }
        }

        if ($evalmode) {
            @tags = $text =~ m/\s(\w+[\w\/]+)\s/g;

            foreach (@tags) {
                my $tag = $_;
                my $repl = %hmeta ? $hmeta{ $tag } : $METADATA{ $tag };
                #print "THE TAGGED '${tag}'\n";
                $repl = $repl ? $repl : $METADATA{ $tag };
                $text =~ s/\s${tag}\s/ \"${repl}\" /;
            }
        }
        #print "TAGGED '${text}'\n";
    }

    return $text;
};

sub get_locale_string {

    my $label = shift;
    my $text = $LOCALES{$label};

    $text = $text ? $text : $label;

    if ($label eq $text) {
        $text =~ s/^(L|TIP)_//g;
        $text =~ s/_/ /g;
        $text =~ s/([\w\']+)/\u\L${1}/g;
    }

    return $text;
};

sub get_default_key {
    my $section = shift;
    my $actions = $ACTIONS->{ $section };
    my $key = $actions-> { "key" };
    return $key;
};

sub get_default_value {
    my $section = shift;
    my $key = shift;

    my $actions = $ACTIONS->{ $section };
    $key = $key ? $key : $actions-> { "key" };

    my $value = $SELECTED{ "selected-${key}" };

    $value = $value ? $value : $actions-> { "defaults/${key}" };

    if ($value =~ m/[%]/) {
        $value = replace_tags( $value, 1 );
    }

    return $value;
};

sub show_text {

    my $label = shift;
    my $tooltip = shift;
    my $value = shift;
    my $showmode = shift;
    my $indent = "    ";

    my $title = get_locale_string($label);
    my $text = get_locale_string($tooltip);

    $title =~ s/([\w\']+)/\u\L${1}/g;

    if ( !$showmode || $showmode != 2) {
        $text =~ s/^/$indent/g;
        $text =~ s/\\n/\n$indent/g;
    }

    if ($showmode && $showmode == 1) {
        $text = replace_html_tags( $text, 1 );
    }

    $text =~ s/(\n\s*){3}/\n\n$indent/g;

    if ($showmode && $showmode == 2) {
        print "[0;1;36m${title}:[0m${text}\n";
    } elsif ($showmode && $showmode >= 3) {
        my $entry = $showmode - 3;
        print "[0;1;36m${entry}# ${title}:[0m\n${text}\n${indent}[0;1;31m[ $value ][0m\n\n";
    } else {
        print "[0;1;36m${title}:[0m\n${text}\n\n";
    }

    STDOUT->autoflush(1);
    STDERR->autoflush(1);
};

sub show_html {
    my $htmlfile = shift;
    my $html = "";

    open (INI, "$htmlfile") || die "Can't open $htmlfile $!\n";

    while (<INI>) {
        chomp;
        $html = "${html}". replace_html_tags( $_ );
    }

    $html =~ s/(\n\s*){3,}/\n\n/g;
    print $html;

    close(INI);
};

sub capture_action {

    my $cmd = shift;
    my $outyes = shift;

    my $line = undef;
    my $rc = 0;

    my $pid = open(PROC, "${cmd}|" ) || return 0;

    while(<PROC>) {

        chomp;

        if ($outyes && $outyes == 1) { print "$_\n"; }

        if (/^(BRZINST|INSTALLER)[:] MESSAGE (.*)$/) {
            my $text = get_locale_string($2);
            print "[0;36m${text} ...[0m\n";
        }
        elsif (/^(BRZINST|INSTALLER)[:] SUCCESS (.*)$/) {
            print "${2} ...\n";
            $rc=1;
        }
        elsif (/^(BRZINST|INSTALLER)[:] WARNING (.*)$/) {
            print "${2} ...\n";
        }
        elsif (/^(BRZINST|INSTALLER)[:] ERROR (.*)$/) {
            print "${2} ...\n";
        }
        elsif (/^(BRZINST|INSTALLER)[:] FAILURE (.*)$/) {
            print "${2} ...\n";
        }
        elsif (/^(BRZINST|INSTALLER)[:] PROGRESS (.*)$/) {
            print "${2} ...\n";
        }
        elsif (/^(BRZINST|INSTALLER)[:] MESGICON (.*)$/) {
            print "${2} ...\n";
        }
    }

    my $status = waitpid( $pid, 0 );

    print "Status: $status\n";
    #print "Status: $status", WEXITSTATUS($status), "\n";

    close(PROC);

    if ($rc == 1 || $status > 0) {
	    #if (WIFEXITED( ${status} ) || $rc == 1) {
        return 1;
    }

    return 0;
};

sub load_config {

    my $cfgfile = shift;
    my $cfgmode = shift;

    my $ordering_found = undef;
    my $backslash = undef;
    my $level = 0;
    my $incr = 0;

    my $cfgkey = undef;
    my $section;
    my $group = "";

    open (INI, "$cfgfile") || die "Can't open $cfgfile: $!\n";

    while (<INI>) {
        chomp;

        if (/^(\#|\/\/).*/) { next; }

        if ($backslash) {
            $backslash = "${backslash}n$_";
            $LOCALES{ $cfgkey } = $backslash;

            if (not /^.*\\$/) {
                $backslash = undef;
            }
            next;
        }

        if (/^\s*\[([\w_-]+)\].*/) {

            if ($level == 1) {
                $section = $1;
            }

            if ($level++ > 0) {
                $group = "${group}/$1";
#print ">>> ${group}\n";
            }

            if (/^\s*\[ordering\].*/) {
                $ordering_found = 1;
            }
        }
        elsif (/^\s*\[\/([\w_-]+)\].*/) {

            $level--;

            $group =~ s/\/${1}$//;
#print "<<< '${group}'\n";

            if (/^\s*\[\/ordering\].*/) {
                $ordering_found = undef;
            }
        }

#    if (/^\W*(\w+)=?(\w+)\W*(#.*)?$/) {
        if ( /^\s*([^=]+?)\s*=\s*(.*?)\s*$/ ) {
            my $key = $1;
            my $value = $2;

            $cfgkey = "$group/$key";
            $cfgkey =~ s/^\///;

            if ($cfgmode) {
                $LOCALES{ $cfgkey } = $value;

            } else {
                $METADATA{ $cfgkey } = $value;

                $cfgkey =~ s/^[^\/]*\///;
                $ACTIONS-> {$section}-> {$cfgkey} = $value;

                if ($ordering_found) {
                     $ORDERING[ $incr++ ] = $key;
                }
            }

            if ($value =~ m/\\$/) {
                $backslash = $value;
            }
        }
    }

    close(INI);
};

sub save_data {

    my $filename = shift;
    my %data = @_;

    return 0 unless $filename;

    open (INI, '>', $filename ) || return 0;

    foreach my $key (sort keys %data) {
        print INI $key, "=", $data{ $key }, "\n";
    }

    close(INI);
};

sub load_data {

    my $cfgfile = shift;
    my $reverse = shift;

    my $incr = 0;
    my $line;
    my %amap;
    my @seq;

    return \%amap unless $cfgfile;

    $cfgfile =~ m/[|,(){}]/ && return \%amap;

    open (INI, "$cfgfile") || return \%amap;

    my @bits = split /\./, $cfgfile;
    my $dtype = pop @bits;

    while (<INI>) {
        chomp;

        if (/^(\#|\/\/).*/) { next; }

        $line = $_;

        if ($dtype eq "map") {
            if ( /^\s*([^=]+?)\s*=\s*(.*?)\s*$/ ) {
                if ($reverse) {
                   $amap{ $2 } = $1;
                } else {
                   $amap{ $1 } = $2;
                }
            }
        } elsif ($dtype eq "lst") {
            $amap{ $line } = $line;
        } elsif ($dtype eq "csv") {
              $seq[ $incr++ ] = $line;
        }
    }

    close(INI);

    if (scalar %amap) { return \%amap; }

    return \@seq;
};

sub load_sequence {

    my $cfgfile = shift;
    my $cfgmode= shift;

    my @sequence;
    my %metadata;

    my $identifier;
    my $incr = -1;
    my $level = 0;
    my $group = "";

    open (INI, "$cfgfile") || die "Can't open $cfgfile: $!\n";

    while (<INI>) {
        chomp;

        if (/^(\#|\/\/).*/) { next; }

        if (/^\s*\[([\w_-]+)\].*/) {
            if ($level == 1) {
                $sequence[++$incr]{ "name" } = $1;
                $identifier = $1;
            }

            if ($level++ > 0) {
                $group = "${group}/$1";
            }
        } elsif (/^\s*\[\/([\w_-]+)\].*/) {
            $level--;
            $group =~ s/\/${1}$//;
        }

        if ( /^\s*([^=]+?)\s*=\s*(.*?)\s*$/ ) {
            my $key = "$group/$1";
            my $value = $2;

            if ($identifier) {
                $key =~ s/^\/[^\/]*\///;

                if ($cfgmode) {
                    $metadata{$identifier}-> {$key} = $value;
                } else {
                    $sequence[$incr]{ $key } = $value;
                }
            }
        }
    }

    close(INI);

    return $cfgmode ? \%metadata : \@sequence;
};

sub eval_cond {
    my $text = shift;
    my $result = shift;
    my $cond = replace_tags( $text, 1 );

    $cond =~ s/\s=\s/ eq /g;
    $cond =~ s/\s\!=/ ne /g;
    $cond =~ s/\s\-o\s/ && /g;
    $cond =~ s/\s\-a\s/ || /g;
    $cond =~ s/^test /\$result = /;

    my @words = $cond =~ m/(\w+)/;

    foreach (@words) {

        my $word = $_;

        if ($word =~ m/^(rm|unlink|find|rsync|ssh|cp|mv)$/) {
            warn "Dangerous command found in string !";
            return 0;
        }

        if (-e $word) {
            warn "Unallowed command found in string !";
            return 0;
        }

        foreach (sort keys %ENV) { 
            my $path = "$ENV{$_}/${word}"; 

            if (-e $path) {
                warn "Unallowed command found in string !";
                return 0;
            }
        }
    }

    eval $cond; warn $@ if $@;

    #print $@ if $@;
    #print "COND -- ${cond} -> ${result} ...\n";

    return $result;
};

sub answer_prompt {
    my $nchoices = shift;
    my $defltval = shift;
    my $object = shift;

    if ($nchoices > 15) {
        print "\n[1mPlease select an entry, press <SPACE> for more, or press <RETURN> for [${defltval}] ![0m ";
    } else {
        print "\n[1mPlease select an entry or press <RETURN> for [${defltval}] ![0m ";
    }

    my $choice = <STDIN>; chomp $choice;
    $choice = $choice ? $choice : $defltval;

    return $choice;
};

sub apply_step {
    my $section = shift;
    my $actions = $ACTIONS-> { $section };
};

sub exec_step {
    my $section = shift;
    my $actions = $ACTIONS-> { $section };
    my $action = $actions-> { "action" };
    my $cmd = replace_tags( $action );
    return capture_action( $cmd );
};

sub show_step {
    my $section = shift;
    my $actions = $ACTIONS-> { $SECTION } unless $section ne $SECTION;
    my $loop_condition = 0;

    if ($actions) {
        my $condition = $actions-> {"condition"};
        if ($condition) {
            eval_cond( $condition ) or return 0;
        }

        my $defltkey = get_default_key( $section );
        my $saveto = replace_tags( $actions-> {"saveto"} );

        my $datafile = replace_tags( $actions-> {"attr-entries"} );
        my %hmeta = %{ load_data( $datafile, 0 ) };

        my $input = $actions-> {"input-widget"};
        if ($input) {
            my $constraint = $actions-> {"input-constraint"};
            my $prompt = get_locale_string( $actions-> {"input-title"} );
            my $choice = 0;

            while(1) {
                print "[1m${prompt}: [0m";

                $choice = <STDIN>; chomp $choice;

                if ($choice && $constraint) {
                    if ($choice =~ m/^${constraint}$/) {
                        last;
                    } else {
                         print "[0;31m>>> Invalid hostname ![0m\n";
                    }
                } elsif ($choice) {
                    last;
                }
                else {
                    $choice = "breezeos";
                }
            }

            if ($choice) {
                $SELECTED{ "selected-${defltkey}" } = $choice;
                $METADATA{ "${SECTION}/${defltkey}" } = $choice;
                my $cmd = replace_tags( $actions-> {"action"}, 1 );
                #capture_action( $cmd, 1 );
            }

            return 1;
        }

ATTR_VALUE_SELECT:
        if ($loop_condition) {
            print "[2J[H";
            STDOUT->autoflush(1);
            STDERR->autoflush(1);
        }

        my $htmlfile = replace_tags( $actions-> {"descr-entries"} );
        if ($htmlfile && $htmlfile =~ m/\/globalicons.seq$/) {
            my $meta = $GLOBALSEQ{ $SECTION };
            my $title = $meta->{ "title" };
            my $tooltip = $meta->{ "description" };

            if ($tooltip =~ m/[.]html$/) {
                show_html( replace_tags( $tooltip ) );
            } else {
                show_text( $title, $tooltip, undef, 1 );
            }
        }
        else {
            my $htmlfile = replace_tags( $actions-> {"description"} );
            if ($htmlfile) {
                show_html( $htmlfile );
            }
        }

        my $cfgfile = replace_tags( $actions-> {"attr-fields"} );
        if ($cfgfile) {
            my @sequence = @{ load_sequence($cfgfile) };
            my $attr_values = "";
            my $attr_label;
            my $incr = 1;

            foreach my $meta (@sequence) {
                my $name = $meta->{ "name" };
                my $widget = $meta->{ "mimetype" };
                my $tooltip = $meta->{ "tooltip" };

                if ($SECTION eq "homepage") {
                    if ($name ne "credits") {
                        show_text( $name, $tooltip, undef, 1 );
                    }
                }
                elsif ($widget eq "widget/label") {
                    $attr_label = $meta->{ "value" };
                }
                else {
                    my $value = %hmeta ? $hmeta{$name} : get_default_value($section, $name);
                    $value = $value ? $value : get_default_value($section, $name);
                    show_text( $attr_label, $tooltip, $value, $incr++ + 3 );
                }
            }

            if ($SECTION eq "homepage") {
                print "\n[1mPlease type one of the above choices, or press <Enter> ![0m ";
                my $choice = <STDIN>; chomp $choice;
                if ($choice) {
                    if ($choice =~ m/^(exit|e|q|quit)$/) {
                        $RUNNING = 0;
                    } else {
                        goto_action( $choice );
                        $CUREVAL = 0;
                    }
                }

                return 0;
            }

            print "\n[1mPlease enter an entry,value pair or press <Enter> to select default values ![0m ";
            my $answer = <STDIN>; chomp $answer;

            if ($answer) {
                my $incr = 1;
                my ( $choice, $value ) = split /[, ]/, $answer;

                foreach my $meta (@sequence) {
                    my $name = $meta->{ "name" };
                    my $widget = $meta->{ "mimetype" };

                    if ($widget ne "widget/label") {
                        if ($choice eq $name ||
                           ($choice =~ m/^[0-9]+$/ && int($choice) == $incr))
                        {
                            $hmeta{$name} = $value;
                        }
                        $incr++;
                    }
                }

                $loop_condition = 1;
                goto ATTR_VALUE_SELECT;
            }

            if ($saveto) {
                if ($saveto =~ m/[\/]/) {
                    save_data( $saveto, %hmeta );
                } else {
                    $saveto = $ENV{"TMP"}. "/". $saveto;
                    save_data( $saveto, %hmeta );
                }
            }

            my $cmd = replace_tags( $actions-> {"action"}, 1, %hmeta );
            if ($cmd) {
                print "\n[1mPlease press <S> to skip or press <Enter> to apply selected values ![0m ";
                my $answer = <STDIN>; chomp $answer;
                #capture_action( $cmd, 1 );
            }
        }

        my $listfile = replace_tags( $actions-> {"list-entries"} );
        if ($listfile) {
            my $incr = 1;
            my $mlen = 1;
            my $nchoices = 0;
            my $cols = $NCOLS / 2;
            my $defltval = get_default_value( $section );

            print "----------------------------------------------------------------------------\n\n";

            my @ameta = undef;
            my %hmeta = %{ load_data( $listfile, 0 ) };

            if (%hmeta) {
                foreach my $key (sort keys %hmeta) {
                    my $len = length get_locale_string($key);
                    $mlen = $mlen < $len ? $len : $mlen;
                    $nchoices++;
                }

                foreach my $key (sort keys %hmeta) {
                    my $text = get_locale_string($key);

                    if ($text =~ m/^[0-9]+#/) {
                        printf "%-${mlen}s -- $hmeta{$key}\n", $text;
                    } else {
                        printf "%3d# %-${mlen}s -- $hmeta{$key}\n", $incr, $text;
                    }
                    $incr++;
                }
            } else {
                @ameta = split /[,|]/, $listfile;

                foreach (@ameta) {
                    print "${incr}# $_\n";
                    $nchoices++;
                    $incr++;
                }
            }

            my $choice = answer_prompt( $nchoices, $defltval, $SECTION );

            $incr = 1;

            if (%hmeta) {
                foreach my $key (sort keys %hmeta) {
                    if ($choice eq $hmeta{$key} ||
                       ($choice =~ m/^[0-9]+$/ && int($choice) == $incr))
                    {
                        my $value = $hmeta{$key};
                        print "Proceeding with $value\n";
                        $SELECTED{ "selected-${defltkey}" } = $value;
                        $METADATA{ "${SECTION}/${defltkey}" } = $value;
                        last;
                    }
                    $incr++;
                }
            } else {
                foreach (@ameta) {
                    if ($choice eq $_ ||
                       ($choice =~ m/^[0-9]+$/ && int($choice) == $incr))
                    {
                        print "Proceeding with $_\n";
                        $SELECTED{ "selected-${defltkey}" } = $_;
                        $METADATA{ "${SECTION}/${defltkey}" } = $_;
                        last;
                    }
                    $incr++;
                }
            }

            return 0;
        }

        my $drvfile = replace_tags( $actions-> {"drive-fields"} );
        if ($drvfile) {
            my @sequence = @{ load_sequence($drvfile) };
            my $drive_values = "";
            my $drive_label;
        }
    } else {
        print "[0;1;31mFailed to match section with page ![0m\n";
    }

    return 1;
};

sub load_actions {
    my $brzdir = $ENV{ "BRZDIR" };
    my $cfgfile = "$brzdir/factory/actions.seq";
    load_config( $cfgfile );
    $MAXSTEPS = scalar(@ORDERING);
};

sub load_locales {
    my $brzdir = $ENV{ "BRZDIR" };
    my $locale = $ENV{ "LOCALE" };
    my $cfgfile = "$brzdir/i18n/en_US.map";
    load_config( $cfgfile, 1 );
};

sub load_globalmesgs {
    my $brzdir = $ENV{ "BRZDIR" };
    my $cfgfile = "$brzdir/fields/globalicons.seq";
    %GLOBALSEQ = %{ load_sequence( $cfgfile, 1) };
};

sub dump_actions() {

    my $section;
    my $property;
    my $key;
    my $incr = 0;

    foreach $section ( keys %$ACTIONS ) {
        my $block = $ACTIONS-> {$section};
        print "[ ${section} ]\n";

        foreach my $property ( keys %$block ) {
            print "${property}=", $block-> {$property}, "\n";
        }

        print "[/ ${section} ]\n\n";
    }

    foreach (@ORDERING) {
        print ">>> ORDERING[", $incr++, "] = $_\n";
    }

    foreach $key ( keys %METADATA ) {
        print ">>> $key = $METADATA{$key}\n";
    }
};

sub start {
    my $path = $ENV{ "PATH" };
    my $brzdir = $ENV{ "BRZDIR" };
    my $prompt = 0;
    my $rc = 0;

    $ENV{ "TMP" } = "C:/mingw64/tmp/";
    $ENV{ "PATH" } = "${path}:${brzdir}/bin";

    load_actions();

    load_locales();

    load_globalmesgs();

    goto_action( "setenv" ) || die "Invalid action specified !";

    while ($RUNNING) {
        print "<<<<<<<<<<<<<<<<<<<<<<<<<<< ${SECTION} [ ${EXEC_MODE} ] <<<<<<<<<<<<<<<<<<<<<<<<<<\n\n";

        $CUREVAL = 1;
        $prompt = 0;

        my $actions = $ACTIONS-> { $SECTION };
        my $nextcmd = $actions-> {"goto"};

        my $batch_cond = $actions-> {"batchmode"};
        if ($batch_cond) {
            if (eval_cond( $batch_cond )) {
                $rc = exec_step( $ORDERING[$STEP] );
            } else {
                $prompt = show_step( $ORDERING[$STEP] );
            }
        }
        elsif ($EXEC_MODE =~ m/^batch$/) {
            $rc = exec_step( $ORDERING[$STEP] );
        } else {
            $prompt = show_step( $ORDERING[$STEP] );
        }

        STDOUT->autoflush(1);
        STDERR->autoflush(1);

        if ($nextcmd && $nextcmd =~ m/^next$/) {
            goto_next() unless $CUREVAL == 0;
        }
        elsif ($prompt && $prompt == 1) {
            print "\n[1mPlease press <Enter> to continue, <Q> to Quit, or <H> for Home ![0m ";
            my $cmd = <STDIN>; chomp $cmd;

            if ($cmd) {
                if ($cmd =~ m/[Qq]|^quit$/) { $RUNNING = 0; last; }
                if ($cmd =~ m/[Hh]|^home$/) { goto_home(); }
            } else {
                goto_next() unless $CUREVAL == 0;
            }
        } else {
            goto_next() unless $CUREVAL == 0;
        }

        print "[2J[H";
        STDOUT->autoflush(1);
        STDERR->autoflush(1);
    }
};

#==================================================
# MAIN STARTS HERE ...
#==================================================

print "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n\n";

capture_action( "/usr/bin/screenfetch", 1 );

print "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n\n";

my $datestring = localtime( time );
print "\nCurrent date: $datestring ...\n";

print "\nScreen size: $NLINES lines and $NCOLS columns ...\n\n";

start();
exit 0;

