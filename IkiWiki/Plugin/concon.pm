#!/usr/bin/perl
package IkiWiki::Plugin::concon;

use warnings;
use strict;
use IkiWiki 3.00;
use Config::Context;

my $ConfObj;

sub import {
	hook(type => "getopt", id => "concon",  call => \&getopt);
	hook(type => "getsetup", id => "concon",  call => \&getsetup);
	hook(type => "checkconfig", id => "concon", call => \&checkconfig);
	hook(type => "scan", id => "concon", call => \&scan, first=>1);
}

sub getopt () {
	eval q{use Getopt::Long};
        error($@) if $@;
        Getopt::Long::Configure('pass_through');
        GetOptions("concon_file=s" => \$config{concon_file});
}

sub getsetup () {
	return
		plugin => {
			description => "Use Config::Context configuration file to set context-sensitive options",
			safe => 1,
			rebuild => undef,
		},
		concon_file => {
			type => "string",
			example => "/home/user/ikiwiki/site.cfg",
			description => "file where the configuration options are set",
			safe => 0,
			rebuild => 0,
		},
}

sub checkconfig () {
    if (!exists $config{concon_file}
	or !defined $config{concon_file})
    {
	error("$config{concon_file} not defined");
	return 0;
    }
    if (exists $config{concon_file}
	and !-f $config{concon_file})
    {
	error("$config{concon_file} not found");
	return 0;
    }
    $ConfObj = Config::Context->new
	(
	 file => $config{concon_file},
	 driver => 'ConfigGeneral',
	 match_sections => [
	 {
	 name          => 'Page',
	 section_type  => 'page',
	 match_type    => 'path',
	 },
	 {
	 name          => 'PageMatch',
	 section_type  => 'page',
	 match_type    => 'regex',
	 },
	 {
	 name          => 'File',
	 section_type  => 'file',
	 match_type    => 'path',
	 },
	 {
	 name          => 'FileMatch',
	 section_type  => 'file',
	 match_type    => 'regex',
	 },
	 ],

	);

    # if using field plugin, register fields
    if (UNIVERSAL::can("IkiWiki::Plugin::field", "import"))
    {
	IkiWiki::Plugin::field::field_register(id=>'concon');
    }
    return 1;
}

sub scan {
    my %params=@_;
    my $page=$params{page};

    my $page_file=$pagesources{$page} || return;

    # clear the info
    delete $pagestate{$page}{'concon'};

    my %config = $ConfObj->context(page=>"/${page}", file=>$page_file);
    # set the pagestate so that other modules can use it.
    $pagestate{$page}{'concon'} = \%config if %config;
} # scan

1;
