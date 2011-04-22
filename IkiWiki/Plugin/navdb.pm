#!/usr/bin/perl
# Ikiwiki navdb plugin.
# Navigation database; saves a subset of the navigation data
# in a separate database to be used by other scripts
# for dynamic navigation.
# The reason for having dynamic navigation is so that
# the whole site doesn't have to be rebuilt when a new page is added
# or a page is deleted.
package IkiWiki::Plugin::navdb;

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::LinkList;
use DB_File::Lock;
use Storable;
use Fcntl qw(:flock O_RDWR O_CREAT O_RDONLY);
use YAML::Any;

sub import {
	hook(type => "getsetup", id => "navdb",  call => \&getsetup);
	hook(type => "checkconfig", id => "navdb", call => \&checkconfig);
	hook(type => "cgi", id => "navdb", call => \&cgi);
	hook(type => "delete", id => "navdb", call => \&delete);
	hook(type => "change", id => "navdb", call => \&change);
}

# ------------------------------------------------------------
# Hooks
# ----------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		navdb_on => {
			type => "boolean",
			example => 0,
			description => "enable or disable navdb",
			safe => 0,
			rebuild => 0,
		},
		navdb_pages => {
			type => "string",
			example => 0,
			description => "which pages' info are saved for the navdb",
			safe => 0,
			rebuild => 0,
		},
		navdb_startlevel => {
			type => "integer",
			example => 0,
			description => "start-level for navigation",
			safe => 0,
			rebuild => 0,
		},
		navdb_cgicache => {
			type => "boolean",
			example => 0,
			description => "use CGI::Cache for caching",
			safe => 0,
			rebuild => 0,
		},
		navdb_prefix => {
			type => "string",
			example => 0,
			description => "optional prefix for navigation urls",
			safe => 0,
			rebuild => 0,
		},
}

sub checkconfig () {
	foreach my $required (qw(url cgiurl)) {
		if (! length $config{$required}) {
			error(sprintf(gettext("Must specify %s when using the %s plugin"), $required, 'navdb'));
		}
	}
	if (!defined $config{navdb_on})
	{
	    $config{navdb_on} = 1;
	}
	if (!defined $config{navdb_pages})
	{
	    $config{navdb_pages} = "* and !*.*";
	}
	if (!defined $config{navdb_prefix})
	{
	    $config{navdb_prefix} = '';
	}
	if (!defined $config{navdb_startlevel})
	{
	    $config{navdb_startlevel} = 2;
	}
	if ($config{navdb_cgicache})
	{
	    eval q{use CGI::Cache};
	    if ($@) {
		error(sprintf(gettext("CGI:Cache needed for caching %s plugin"), 'navdb'));
	    }
	}
}

sub cgi ($) {
    my $cgi=shift;

    if (defined $cgi->param('do')
	and $cgi->param('do') eq 'navigation')
    {
	IkiWiki::decode_cgi_utf8($cgi);
	my $page=$cgi->param('page');

	if (! defined $page || $page !~ /$config{wiki_file_regexp}/) {
		error("invalid page parameter");
	}

	if ($config{navdb_cgicache})
	{
	    setup_cache();
	    CGI::Cache::set_key($cgi->Vars);
	    # short-circuit the rest if already cached
	    CGI::Cache::start() or exit(0);
	}
	my $tree = do_navtree($page);

	print "Content-type: text/plain\n\n";
	print $tree, "\n";

	if ($config{navdb_cgicache})
	{
	    CGI::Cache::stop();
	}

	exit(0);
    }
}

sub delete (@) {
    my @files=@_;

    my $navfile="$config{wikistatedir}/navdb";

    # clear the cache if there is one
    my $cachedir="$config{wikistatedir}/cgi_cache";
    if ($config{navdb_cgicache} and -d $cachedir)
    {
	setup_cache();
	CGI::Cache::clear_cache();
    }
    if (-d $config{wikistatedir}
	and -e $navfile)
    {
	# delete the navdata related to these pages
	my %roots = ();
	foreach my $file (@files)
	{
	    my $page=pagename($file);
	    if (!pagespec_match($page, $config{navdb_pages}))
	    {
		next;
	    }
	    $roots{get_root_page($page)} = 1;
	}

	my %dbhash;
	tie(%dbhash, "DB_File::Lock", $navfile, O_CREAT|O_RDWR, 0666, $DB_HASH, "write")
	    or error("Cannot open file '$navfile': $!") ;

	# update the navdata related to these pages
	foreach my $root (keys %roots)
	{
	    debug("navdb: updating $root");
	    my $tree = build_2nd_level_tree($root);
	    $dbhash{$root} = Storable::freeze($tree);
	}
	untie %dbhash;
    }

} # delete

sub change (@) {
    my @files=@_;

    # Redo navigation because of changed pages
    # Make note of the roots of the changed
    # pages, and redo the matching pages' nav.
    # Note we record this in a hash, because
    # pages could have the same roots,
    # so we want to avoid duplicates.
    my %roots = ();
    foreach my $file (@files) {
	my $page=pagename($file);
	if (!pagespec_match($page, $config{navdb_pages}))
	{
	    next;
	}
	my $root = get_root_page($page);
	$roots{$root} = 1;
    }
    my %new_nav_data = ();
    foreach my $root (sort keys %roots)
    {
	debug("navigation for $root");
	redo_navdata(\%new_nav_data, $root);
    }
    save_navdata(\%new_nav_data);
} # change

# ------------------------------------------------------------
# Private Functions
# ----------------------------

sub redo_navdata ($$) {
    my $new_nav_data = shift;
    my $root = shift;

    my $tree = build_2nd_level_tree($root);
    $new_nav_data->{$root} = $tree;

} # redo_navdata

sub do_navtree ($$) {
    my $page = shift;

    if (!$page)
    {
	return '';
    }

    # This assumes that the top-level is in the form of
    # http://example.com/
    # NOT http://example.com/~user/
    my $current_url = IkiWiki::urlto($page, '', 1);
    $current_url =~ s/index\.\w+$//;
    $current_url =~ s/^http:\/\/[\w\.]+//;
    if ($config{navdb_prefix})
    {
	my $np = $config{navdb_prefix};
	$current_url =~ s/^\Q$np\E//;
    }
    my $ndata = get_2nd_level_tree($page);
    my $html = HTML::LinkList::nav_tree
	(
	 prefix_url=>$config{navdb_prefix},
	 paths=>$ndata->{uris},
	 preserve_order=>1,
	 preserve_paths=>1,
	 labels=>$ndata->{titles},
	 current_url => $current_url,
	 pre_current_parent=>'<span class="current">',
	 post_current_parent=>'</span>',
	 pre_active_item=>'<strong>',
	 post_active_item=>'</strong>',
	 start_depth=>$config{navdb_startlevel},
	 hide_ext=>1,);

    return $html;
} # do_navtree

sub save_navdata {
    my $newnav = shift;

    if (! -d $config{wikistatedir}) {
	mkdir($config{wikistatedir});
    }

    # clear the cache if there is one
    my $cachedir="$config{wikistatedir}/cgi_cache";
    if ($config{navdb_cgicache} and -d $cachedir)
    {
	setup_cache();
	CGI::Cache::clear_cache();
    }

    my $navfile="$config{wikistatedir}/navdb";
    my %dbhash;
    tie(%dbhash, "DB_File::Lock", $navfile, O_CREAT|O_RDWR, 0666, $DB_HASH, "write")
	or error("Cannot open file '$navfile': $!");

    foreach my $key (keys %{$newnav})
    {
	$dbhash{$key} = Storable::freeze($newnav->{$key});
    }

    untie %dbhash;
} # save_navdata

# Get the root-page of the tree to which
# this page belongs:
# - 2nd-level root if the startlevel is 2 or higher
# - actual root if the startlevel is 1
sub get_root_page {
    my $page = shift;

    my $root;
    if ($config{navdb_startlevel} == 1)
    {
	$root = '/';
    }
    else
    {
	# find the root of this tree
	if ($page =~ m{^([-\w]+)/})
	{
	    $root = $1;
	}
	else
	{
	    $root = $page;
	}
    }
    return $root;
} # get_root_page

# get the data from the 2nd-level down,
# starting from the given root
sub build_2nd_level_tree {
    my $root = shift;
    
    # Use pagespec_match because we don't want to have to deal
    # with dependencies here
    my @candidates = keys %pagesources;
    eval q{use Sort::Naturally};
    if ($@) {
	@candidates = sort(@candidates);
    }
    else
    {
	@candidates = nsort(@candidates);
    }
    my @matches = ();
    my @nav_uris = ();
    my %htitles = ();
    my $pagespec = $config{navdb_pages};
    $pagespec .= " and ${root}*" if ($root ne '/');
    foreach my $p (@candidates)
    {
	if (pagespec_match($p, $pagespec))
	{
	    my $uri = "/$p/";
	    push @matches, $p;
	    push @nav_uris, $uri;
	    if (exists $pagestate{$p}
		and exists $pagestate{$p}{meta}{title})
	    {
		$htitles{$uri} = $pagestate{$p}{meta}{title};
		$htitles{$uri} =~ s{ & }{&amp;}g;
		$htitles{$uri} =~ s{<}{&lt;}g;
		$htitles{$uri} =~ s{>}{&gt;}g;
	    }
	}
    }
    return {
	pages => \@matches,
	uris => \@nav_uris,
	titles => \%htitles,
    };
} # build_2nd_level_tree

# read the 2nd-level-tree from the database
sub read_2nd_level_tree {
    my $root = shift;

    my $navfile="$config{wikistatedir}/navdb";
    if (!-e $navfile)
    {
	return undef;
    }
    my %dbhash;
    tie(%dbhash, "DB_File::Lock", $navfile, O_RDONLY, 0666, $DB_HASH, "read")
	or error("Cannot open file '$navfile': $!") ;

    my $tree = undef;
    if (exists $dbhash{$root}
	and defined $dbhash{$root})
    {
	$tree = Storable::thaw($dbhash{$root});
    }
    untie %dbhash;
    return $tree;
} #read_2nd_level_tree

# get the 2nd-level tree, either by reading
# it or by making it
sub get_2nd_level_tree {
    my $page = shift;

    my $root = get_root_page($page);
    my $tree = read_2nd_level_tree($root);
    if (!defined $tree)
    {
	if (!defined %pagestate
	    or !defined $pagestate{$page})
	{
	    IkiWiki::loadindex();
	}
	$tree = build_2nd_level_tree($root);
	my %hash = ();
	$hash{$root} = $tree;
	save_navdata(\%hash);
    }
    return $tree;
} # get_2nd_level_tree

sub setup_cache {
    CGI::Cache::setup( { cache_options =>
		       { cache_root => "$config{wikistatedir}/cgi_cache",
		       namespace => 'navdb',
		       directory_umask => 077,
		       max_size => 20 * 1024 * 1024,
		       }
		       } );
} # setup_cache
1;
