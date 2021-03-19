#!/usr/bin/perl
#
# Collects any wiki links from Markdown files within the defined directory
# and adds a "## Backlinks" -section containing all links to the file.
#
# Heavily influenced by https://github.com/andymatuschak/note-link-janitor
#
# Links are kept in order so we do not need to update any files unless 
# there has been changes in links.
#
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
my %opt = (
    link_preference => 'title'
);
my %md_files = ();

# What character in a link to identify as a heading separator. In Bear this is a slash, ie. '/'.
my $hs = '/';

GetOptions(
    "d=s"  => \$opt{dir},
    "b=s"  => \$opt{backup_dir},
    "v"    => \$opt{verbose},
    "r"    => \$opt{recursive},
    "l=s"  => \$opt{link_preference},
    "hs=s" => \$hs
) or _help();

_prepare();
_collect_backlinks();
_create_link_blocks();
_update_link_blocks();
_info("Completed");

#
# Helper subs
#
sub _help {
    print "usage: $0 -d /path/to/directory [-b /path/to/backup_directory] [-v] [-r] [-l title|name] [-hs char]\n";
    print "-v = verbose output\n";
    print "-r = recursive search from defined folder. Default is to search 1 level only.\n";
    print "-l   defines if we should read the link target from filename or the title of the document\n";
    print "     defaults to 'title'\n";
    print "-hs  defines a separator character for sub heading links. Defaults to '/'\n";
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
    if ($opt{backup_dir} && !-d $opt{backup_dir}) {
        _info("Creating directory $opt{backup_dir}");
        make_path($opt{backup_dir}, { mode => 0750 });
    }

    $opt{backup_dir} =~ s/\/+$// if $opt{backup_dir};

    if ($opt{link_preference} !~ /^(title|name)$/) {
        print "ERROR: link_preference should be either 'title' or 'name'\n";
        exit 1;
    }

    if (length($hs) > 1 || $hs =~ /[a-zA-Z0-9]/) {
        print "ERROR: -hs should be a single character and not a letter or a number\n";
        exit 1;
    }
}

sub _backup {
    return 1 unless $opt{backup_dir};
    my $f = shift;
    if (-d $opt{backup_dir} && -f $f) {
        my $file_path = dirname($f);
        $file_path =~ s/^$opt{dir}\/+//;
        my $target_dir = "$opt{backup_dir}/$file_path";
        if (!-d "$opt{backup_dir}/$file_path") {
            make_path($target_dir, { mode => 0750 });
        }
        _info("Backing up $f to $target_dir");
        return copy($f, $target_dir);
    }
    return 1;
}

#
# The works
#
# This collects all wiki links in all files that are not within a Backlinks block
sub _collect_backlinks {
    my $search_opt = "-depth 1";
    $search_opt = "" if $opt{recursive};
    my @md_files = `find "$opt{dir}" -name "*.md" -type f $search_opt`;

    unless (@md_files) {
        _info("No markdown files found in $opt{dir}. Nothing to do.");
        exit;
    }

    foreach (@md_files) {
        chomp;
        my $full_path = dirname($_);
        my $file_name = basename($_);
        $file_name =~ s/\.md$//;
        my $relative_path = $full_path;
        $relative_path =~ s/^$opt{dir}\/?//;

        if ($relative_path =~ /^\./) {
            next;
        }

        # If multiple files with same name, this only includes the last one
        $md_files{$file_name}->{full_path} = $full_path;
        $md_files{$file_name}->{link} = $file_name;
    }

    _info("Collecting backlinks");
    my $file_cnt = 0;
    my $link_cnt = 0;

    foreach (@md_files) {
        chomp;
        my $relative_path = $_;
        $relative_path =~ s/^$opt{dir}\/?//;

        if ($relative_path =~ /^\./) {
            next;
        }

        if (open(F, "$_")) {
            my $first_line = "";
            $file_cnt++;
            my $file_name = basename($_);
            $file_name =~ s/\.md$//;

            my $in_backlinks = "";
            while (<F>) {
                chomp;

                if (!$first_line) {
                    $first_line = $_;

                    if ($first_line =~ /^#\s+/) {
                        $first_line =~ s/^#\s+//;
                        if ($opt{link_preference} eq 'title' && $first_line !~ /^$file_name/) {
                            $md_files{$file_name}->{link} = $first_line;
                        }
                    }
                }

                if (/^## Backlinks/) {
                    $in_backlinks = 1;
                    next;
                }
                else {
                    if ($in_backlinks && /^(#.*|\s+|<!--.*)?$/) {
                        $in_backlinks = "";
                    }
                    elsif (!$in_backlinks) {
                        if (/[^\!]\[\[[^\]]*\]\]/) {
                            my $link = $_;
                            while ($link =~ /\[\[([^\]]*)\]\]/g) {
                                my $current_link = $1;
                                if ($current_link =~ /$hs/) {
                                    my @tmp = split($hs, $current_link);
                                    $current_link = $tmp[0];
                                }

                                if ($md_files{$current_link}) {
                                    $link_cnt++;
                                    $links->{$current_link}->{$file_name}->{sha256_hex($_)} = $_;
                                }
                            }
                        }
                    }
                }
            }
        }
        else {
            _err("Failed to open $_ for reading:", $!);
        }
    }

    _info("$link_cnt links found from $file_cnt files");
}

# This creates link blocks based on the collected data
sub _create_link_blocks {
    _info("Creating link blocks");
    foreach (sort keys %{$links}) {
        my $block = "## Backlinks\n";
        my $link = $links->{$_};
        foreach (sort keys %{$link}) {
            my $t = $_;
            $block .= "- [[$md_files{$t}->{link}]]\n";
            my $l = $link->{$t};
            foreach (sort keys %{$l}) {
                my $s = $_;
                $l->{$s} =~ s/^(-|\*)(\s+)?//;
                $block .= "    - $l->{$s}\n";
            }
        }

        $blocks{$_} = $block;
    }
}

# This places a Backlinks block within each file to which a wiki link exists
sub _update_link_blocks {
    _info("Updating link blocks in files");
    my $cnt = 0;

    foreach (sort keys %blocks) {
        chomp;
        my $file_name = $_;
        my $file_path = $md_files{$file_name}->{full_path};
        my $file = "$file_path/$file_name.md";

        if (open(F, $file)) {
            my @blocks = "";
            my $in_backlinks = "";
            my $pos = 0;
            my $l = 0;
            my $lc = 0;

            while (<F>) {
                my $r = $_;
                if ($r =~ /^## Backlinks/) {
                    $in_backlinks = 1;
                    next;
                }
                else {
                    my $t = $r;
                    chomp($t);
                    if ($in_backlinks && $t !~ /^(\s+)?-\s+/) {
                        $in_backlinks = "";
                        if ($t !~ /^(\s+)?$/) {
                            push(@blocks, $r);

                            if ($t =~ /^(#[a-zA-Z0-9].*|<!--.*)/) {
                                $pos = $l unless $lc;
                                $lc = 1;
                            }
                            $l++;
                        }
                    }
                    elsif (!$in_backlinks) {
                        if ($t =~ /^(#[a-zA-Z0-9].*|<!--.*)/) {
                            $pos = $l unless $lc;
                            $lc = 1;
                        }
                        elsif ($t !~ /^(#[a-zA-Z0-9].*|<!--.*|\s+)?$/) {
                            $lc = 0;
                        }

                        push(@blocks, $r);
                        $l++;
                    }
                }
            }
            close F;

            my $block = $blocks{$file_name};

            if ($blocks[$pos - 1] !~ /^(\s+|---)?$/) {
                $block = "\n$block";
            }

            if ($blocks[$pos - 1] !~ /^---$/ && $blocks[$pos - 2] !~ /^---$/) {
                $block = "---\n$block";
            }

            if ($blocks[-1] !~ /\n$/) {
                push(@blocks, "\n\n");
            }

            if ($pos < 2) {
                push(@blocks, "$block\n");
            }
            else {
                splice(@blocks, $pos, 0, "$block\n");
            }

            my $tmp_file = "$file.tmp";
            if (open(O, ">$tmp_file")) {
                print O join('', @blocks);
                close O;

                if (compare($tmp_file, $file) == 0) {
                    unlink($tmp_file);
                }
                else {
                    if (!_backup($file)) {
                        _err("Failed to backup $file");
                        unlink($tmp_file);
                        next;
                    }
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
