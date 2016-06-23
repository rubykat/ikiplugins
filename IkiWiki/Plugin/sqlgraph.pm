#!/usr/bin/perl
# Report on a SQLite database and make a graphvis graph
package IkiWiki::Plugin::sqlgraph;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::sqlgraph - report on a SQLite database and make a graphvis graph

=head1 VERSION

This describes version B<1.20120204> of IkiWiki::Plugin::sqlgraph

=cut

our $VERSION = '0.20160623';

=head1 PREREQUISITES

    IkiWiki
    DBI
    DBD::SQLite
    Text::NeatTemplate
    SQLite::Work
    IkiWiki::Plugin::sqlreport
    IkiWiki::Plugin::graphviz

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2016 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use DBI;
use POSIX;
use YAML;
use Text::NeatTemplate;
use SQLite::Work;

my %Databases = ();
my $DBs_Connected = 0;

sub import {
    IkiWiki::loadplugin('sqlreport');
    IkiWiki::loadplugin('graphviz');
    hook(type => "getsetup", id => "sqlgraph",  call => \&getsetup);
    hook(type => "preprocess", id => "sqlgraph", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "misc",
		},
}

sub preprocess (@) {
    my %params=@_;
    my $page=$params{page};
    foreach my $p (qw(database table where))
    {
	if (!exists $params{$p})
	{
	    error gettext("sqlgraph: missing $p parameter");
	}
    }
    $params{layout} = 'none';
    $params{report_style} = 'bare';
    $params{report_div} = '';
    if (!exists $config{sqlreport_databases}->{$params{database}})
    {
	error(gettext(sprintf('sqlgraph: database %s does not exist',
		$params{database})));
    }
    my $graph = '';
    my $out = '';

    $graph = IkiWiki::Plugin::sqlreport::preprocess(%params);
    if ($params{pre_graph})
    {
        $graph = $params{pre_graph} . "\n" . $graph;
    }
    if ($params{where2} and $params{row_template2})
    {
        my $graph2 = IkiWiki::Plugin::sqlreport::preprocess(%params, where=>$params{where2}, row_template=>$params{row_template2});
        $graph = $graph . "\n" . $graph2;
    }
    print STDERR $graph, "\n";
    # now take that output
    # and use it as the source of a graphviz graph
    $out = IkiWiki::Plugin::graphviz::graph(%params, page=>$page, src=>$graph);

    return $out;
} # preprocess

1
