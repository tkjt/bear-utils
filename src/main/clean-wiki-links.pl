#!/usr/bin/perl
#
# Clears ## Backlinks -section found from Markdown files.
#
# Author: Teemu Turpeinen, 2021
#

use strict;
use warnings;
use File::Basename;
use File::Compare;
use POSIX qw(strftime);
use Getopt::Long;

my $links = ();
my %blocks = ();
my %opt = ();
my %md_files = ();

GetOptions(
    "d=s" => \$opt{dir},
    "v"   => \$opt{verbose},
    "r"   => \$opt{recursive}
) or _help();

_prepare();
_remove_link_blocks();
_info("Completed");

#
# Helper subs
#
sub _help {
    print "usage: $0 -d /path/to/directory [-v] [-r]\n";
    print "-v = verbose output\n";
    print "-r = recursive search from defined folder. Default is to search 1 level only.\n";
    exit;
}

sub _info {
    return unless $opt{verbose};
    my $msg = join(" ", @_);
    print strftime("%Y-%m-%d %H:%M:%S", localtime(time)) . " - $msg\n" if $msg;
}

sub _err {
    my $msg = join(" ", @_);
    print STDERR strftime("%Y-%m-%d %H:%M:%S", localtime(time)) . " - [ERROR] $msg\n" if $msg;
}

sub _prepare {
    _help() unless ($opt{dir} && -d $opt{dir});
}

#
# The works
#
sub _remove_link_blocks {
    _info("Removing link blocks in files");
    my $cnt = 0;

    my $search_opt = "-depth 1";
    $search_opt = "" if $opt{recursive};
    my @md_files = `find "$opt{dir}" -name "*.md" -type f $search_opt`;

    unless (@md_files) {
        _info("No markdown files found in $opt{dir}. Nothing to do.");
        return;
    }

    foreach (@md_files) {
        chomp;
        my $file = $_;

        if (open(F, $file)) {
            my @blocks = "";
            my $in_backlinks = "";

            while (<F>) {
                my $r = $_;
                if ($r =~ /^## Backlinks/) {
                    my $element = $blocks[-1] ;
                    chomp($element) ;
                    while ($element =~ /^(---)?$/) {
                        pop(@blocks) ;
                        $element = $blocks[-1] ;
                        chomp($element) ;
                    }
                    push(@blocks, "\n") ;
                    $in_backlinks = 1;
                    next;
                }
                else {
                    my $t = $r;
                    chomp($t);
                    if ($in_backlinks && $t !~ /^(\s+)?-\s+/) {
                        $in_backlinks = "";
                        push(@blocks, $r);
                    }
                    elsif (!$in_backlinks) {
                        push(@blocks, $r) ;
                    }
                }
            }
            close F;

            my $tmp_file = "$file.tmp";
            if (open(O, ">$tmp_file")) {
                print O join('', @blocks);
                close O;

                if (compare($tmp_file, $file) == 0) {
                    unlink($tmp_file);
                }
                else {
                    move($tmp_file, $file);
                    _info("Updated $file");
                    $cnt++;
                }
            }
            else {
                _err("Failed to write $tmp_file: $!");
            }
        }
        else {
            _err("Failed to read $file: $!");
        }
    }
    _info("$cnt file(s) were updated");
}
