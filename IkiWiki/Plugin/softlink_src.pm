#!/usr/bin/perl
# Ikiwiki softlink_src plugin; common customizations for my IkiWikis.
package IkiWiki::Plugin::softlink_src;

use warnings;
use strict;
use IkiWiki 3.00;

my %OrigSubs = ();

sub import {
    $OrigSubs{find_src_files} = \&find_src_files;
    inject(name => 'IkiWiki::find_src_files', call => \&my_find_src_files);
}

#-------------------------------------------------------
# Injected functions
#-------------------------------------------------------

sub my_find_src_files () {
	my @files;
	my %pages;
	eval {use File::Find};
	error($@) if $@;

	my ($page, $dir, $underlay);
	my $helper=sub {
		my $file=IkiWiki::decode_utf8($_);

		return if -l $file || -d _;
		$file=~s/^\Q$dir\E\/?//;
		return if ! length $file;
		$page = IkiWiki::pagename($file);
		if (! exists $pagesources{$page} &&
		    IkiWiki::file_pruned($file)) {
			$File::Find::prune=1;
			return;
		}

		my ($f) = $file =~ /$config{wiki_file_regexp}/; # untaint
		if (! defined $f) {
			warn(sprintf(gettext("skipping bad filename %s"), $file)."\n");
			return;
		}
	
		if ($underlay) {
			# avoid underlaydir override attacks; see security.mdwn
			if (! -l "$config{srcdir}/$f" && ! -e _) {
				if (! $pages{$page}) {
					push @files, $f;
					$pages{$page}=1;
				}
			}
		}
		else {
			push @files, $f;
			if ($pages{$page}) {
				debug(sprintf(gettext("%s has multiple possible source pages"), $page));
			}
			$pages{$page}=1;
		}
	};

	find({
		no_chdir => 1,
		wanted => $helper,
	}, $dir=$config{srcdir});
	$underlay=1;
	foreach (@{$config{underlaydirs}}, $config{underlaydir}) {
		find({
			no_chdir => 1,
			follow=>1,
			wanted => $helper,
		}, $dir=$_);
	};
	return \@files, \%pages;
} # my_find_src_files

1;
