#!/usr/bin/perl
#
# Clears ## Backlinks -section found from Markdown files. Also removes tags and comments after Backlinks.
#
# Author: Teemu Turpeinen, 2021
#

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Basename;
use File::Compare;
use File::Copy;
use File::Path qw(make_path);
use POSIX qw(strftime);
use Getopt::Long;

my $links = ();
my %blocks = ();
my %opt = ();
my %md_files = ();

GetOptions(
    "d=s" => \$opt{dir},
    "v"   => \$opt{verbose},
    "r"   => \$opt{recursive},
    "c"   => \$opt{comments},
    "t"   => \$opt{tags}
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
    print "-c = clean comments after backlinks\n" ;
    print "-t = clean tags after backlinks\n" ;
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
            my $after_backlinks = "";
            my $in_comment = "" ;

            while (<F>) {
                my $r = $_;
                if ($r =~ /^## Backlinks/) {
                    my $element = $blocks[-1] ;
                    chomp($element) ;
                    while ($element =~ /^(---|- - - -|\s+)?$/) {
                        pop(@blocks) ;
                        $element = $blocks[-1] ;
                        chomp($element) ;
                    }
                    push(@blocks, "\n") ;
                    $in_backlinks = 1;
                    $after_backlinks = 1;
                    next;
                }
                else {
                    my $t = $r;
                    chomp($t);
                    if ($in_backlinks && $t !~ /^(\s+)?(-|\*)\s+/) {
                        $in_backlinks = "";

                        if ($opt{tags} && $t =~ /^#[a-zA-Z0-9]/) {
                            next ;
                        } 

                        if ($opt{comments} && $t =~ /^(\s+)?<!--/) {
                            $in_comment = 1 ;
                            next ;
                        }

                        if ($opt{comments} && $in_comment && $t =~ /-->/) {
                            $in_comment = "" ;
                            next ;
                        }

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
