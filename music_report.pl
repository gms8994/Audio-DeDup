#!/usr/bin/perl -w

use strict;
use warnings;

use Audio::FLAC::Header;
use Data::Dumper;
use File::Find;
use List::MoreUtils qw/ uniq /;
use MP3::Tag;
use Number::Bytes::Human qw/ format_bytes /;
use Ogg::Vorbis::Header;

my %files;
my $size_saved = 0;

find ({ wanted => \&wanted, preprocess => \&preproc }, "/opt/Music");

warn format_bytes($size_saved);

sub preproc {
	my (@dirs) = @_;

	@dirs = sort(@dirs);

	return @dirs;
}

sub wanted {
	return unless -f $File::Find::name;

    my $file = $File::Find::name;

    if ($file =~ /mp3$/i) {
        my $mp3 = MP3::Tag->new($file);
        return unless $mp3;

        my ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();

        my $rate;
        eval { $rate = $mp3->bitrate_kbps(); };
        
        # don't put it in the hash, just skip
        if ($@) { 
			$MP3::Info::try_harder = 5;

			eval { $rate = $mp3->bitrate_kbps(); };

			if ($@) {
				warn "Error getting the bitrate: $@";
				return;
			}
		}

        &addToHash($artist, $album, $title, $rate, $file);
    } elsif ($file =~ /ogg$/i) {
        my $ogg = Ogg::Vorbis::Header->new($file);
		return unless $ogg;

        my $artist = $ogg->comment('ARTIST');
        my $album = $ogg->comment('ALBUM');
        my $title = $ogg->comment('TITLE');
        my $rate = $ogg->info('bitrate_nominal') / 1024;

        &addToHash($artist, $album, $title, $rate, $file);
    } elsif ($file =~ /flac$/i) {
        my $flac = Audio::FLAC::Header->new($file);
        return unless $flac;

        my $artist = $flac->tags('ARTIST');
        my $album = $flac->tags('ALBUM');
        my $title = $flac->tags('TITLE');
        my $rate = "inf";

        &addToHash($artist, $album, $title, $rate, $file);
	} elsif ($file =~ /(jpe?g|png|txt|ini)$/i) {
    } else {
		# warn "Not doing anything with $file";
	}
}

sub addToHash {
    my ($artist, $album, $title, $rate, $file) = @_;

    return unless $artist && $album && $title;
    return if ($artist =~ /^\d+$/ && $album =~ /^\d+$/ && $title =~ /^\d+$/);

	### figure out a better way for this; the flac conversion uses these values
	# $title =~ s/\W//g;
	# $title = lc($title); ## lower the title

	# $artist =~ s/\W//g;
	# $artist = lc($artist);

	# $album =~ s/\W//g;
	# $album = lc($album);

	# $title =~ s/^the //;
	# $title =~ s/, the$//;

	# $artist =~ s/^the //;
	# $artist =~ s/, the$//;

	# $album =~ s/^the //;
	# $album =~ s/, the$//;

    if (defined($files{$artist}{$album}{$title})) {
        my $e_file = $files{$artist}{$album}{$title}{'file'};
        my $e_rate = $files{$artist}{$album}{$title}{'rate'};

        if ($file =~ /mp3$/i && $e_file =~ /mp3$/i) {
            print "Quality:\n";
            if ($e_rate > $rate) {
                print "\tDelete: $file (against $e_file)\n";
                $size_saved += ( -s $file );
                unlink $file;
            } else {
                print "\tDelete: $e_file (against $file)\n";
                $size_saved += ( -s $e_file );
                unlink $e_file;
            }
        ### mp3|ogg
        } elsif ($file =~ /mp3$/i && $e_file =~ /ogg$/i) {
            print "$e_file is an ogg, and we have an mp3! delete it\n";
            $size_saved += ( -s $e_file );
            return;
        } elsif ($file =~ /ogg$/i && $e_file =~ /mp3$/i) {
            print "$file is an ogg, and we have an mp3! delete it\n";
            $size_saved += ( -s $file );
            return;
        ### mp3/ogg|flac
        } elsif ($file =~ /(mp3|ogg)$/i && $e_file =~ /flac$/i) {
            print "FLAC:\n";
            print "\tDelete the file: $file\n";
            unlink $file;
            print "\tRe-encode the flac: $e_file\n";
            $file =~ s/ogg$/mp3/;
            my $command = "flac -dc \"$e_file\" | lame -b 256 --ignore-tag-errors --tt \"$title\" --tl \"$album\" --ta \"$artist\" --add-id3v2 - \"$file\" 2>&1";
            `$command`;
            $size_saved += ( -s $e_file );
            print "\tAnd delete the flac: $e_file\n";
            unlink $e_file;
            return;
        } elsif ($file =~ /flac$/i && $e_file =~ /(mp3|ogg)$/i) {
            print "FLAC:\n";
            print "\tDelete the file: $e_file\n";
            unlink $e_file;
            print "\tRe-encode the flac: $file\n";
            $file =~ s/ogg$/mp3/;
            my $command = "flac -dc \"$file\" | lame -b 256 --ignore-tag-errors --tt \"$title\" --tl \"$album\" --ta \"$artist\" --add-id3v2 - \"$e_file\" 2>&1";
            `$command`;
            $size_saved += ( -s $file );
            print "\tAnd delete the flac: $file\n";
            unlink $file;
            return;
        } else {
            #print "$file -- $e_file\n";
            print "\$file and \$e_file are the \"same\", but not different enough\n\n";
        }

        print "$file already exists from somewhere else....\n";
        return;
    } else {
		# print "First time seeing content like $file\n";
	}


    $files{$artist}{$album}{$title}{'file'} = $file;
    $files{$artist}{$album}{$title}{'rate'} = $rate;
}
