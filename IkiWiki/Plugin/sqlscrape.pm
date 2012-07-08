#!/usr/bin/perl
# Report on a SQLite database
package IkiWiki::Plugin::sqlscrape;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::sqlscrape - report on a SQLite database

=head1 VERSION

This describes version B<1.20120204> of IkiWiki::Plugin::sqlscrape

=cut

our $VERSION = '1.20120204';

=head1 PREREQUISITES

    IkiWiki
    DBI
    DBD::SQLite
    Text::NeatTemplate

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2012 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use DBI;
use POSIX;
use YAML;

my $Database;
my $Transaction_On = 0;
my $Num_Trans = 0;

sub import {
    hook(type => "getsetup", id => "sqlscrape",  call => \&getsetup);
    hook(type => "checkconfig", id => "sqlscrape", call => \&checkconfig);
    hook(type => "needsbuild", id => "sqlscrape", call => \&needsbuild);
    hook(type => "scan", id => "sqlscrape", call => \&scan, last=>1);
    hook(type => "format", id => "sqlscrape", call => \&format, first=>1);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "misc",
		},
		sqlscrape_database => {
			type => "string",
			example => "sqlscrape_database => '/home/fred/mydb.sqlite',",
			description => "name of the SQLite database to update",
			safe => 0,
			rebuild => undef,
		},
		sqlscrape_fields => {
			type => "array",
			example => "sqlscrape_database => [qw(title author description)],",
			description => "fields to store in the database",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {

    if (!exists $config{sqlscrape_database})
    {
        # set a default database
        $config{sqlscrape_database} = 
            "$config{wikistatedir}/ikiwiki.sqlite";
    }
    if (!exists $config{sqlscrape_fields})
    {
        # set default fields
        $config{sqlscrape_fields} = [qw(title pagetitle baseurl parent_page basename description)];
    }
    my $file = $config{sqlscrape_database};
    my $creating_db = 0;
    if (!-r $file)
    {
        $creating_db = 1;
    }
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file", "", "");
    if (!$dbh)
    {
        error(gettext("Can't connect to $file: $DBI::errstr"));
    }
    $dbh->{sqlite_unicode} = 1;

    # Create the pagefields table if it doesn't exist
    my @field_defs = ();
    foreach my $field (@{$config{sqlscrape_fields}})
    {
        if (exists $config{sqlscrape_field_types}->{$field})
        {
            push @field_defs, $field . ' ' . $config{sqlscrape_field_types}->{$field};
        }
        else
        {
            push @field_defs, $field;
        }
    }
    my $q = "CREATE TABLE IF NOT EXISTS pagefields (page PRIMARY KEY, "
        . join(", ", @field_defs) .");";
    my $ret = $dbh->do($q);
    if (!$ret)
    {
        error(gettext("sqlscrape failed '$q' : $DBI::errstr"));
    }
    $Database = $dbh;
    $Transaction_On = 0;
}

sub needsbuild {
    my $needsbuild = shift;
    my $deleted = shift;

    if (!$deleted or !ref $deleted)
    {
	return $needsbuild;
    }
    if (!$Database)
    {
	return $needsbuild;
    }

    my $ret;
    if (!$Transaction_On)
    {
	$ret = $Database->do("BEGIN TRANSACTION;");
	if (!$ret)
	{
	    error(gettext("sqlscrape in needsbuild failed BEGIN TRANSACTION : $DBI::errstr"));
	}
	$Transaction_On = 1;
    }
    foreach my $file (@{$deleted})
    {
	my $page=pagename($file);
	my $q = "DELETE FROM pagefields WHERE page = '$page';";
	$ret = $Database->do($q);
	if (!$ret)
	{
	    error(gettext("sqlscrape failed DELETE '$q' : $DBI::errstr"));
	}
    }
    # finish the transaction now
    if ($Transaction_On)
    {
	my $ret = $Database->do("COMMIT;");
	if (!$ret)
	{
	    error(gettext("sqlscrape in needsbuild failed COMMIT : $DBI::errstr"));
	}
	$Transaction_On = 0;
    }

    return $needsbuild;
} # needsbuild

sub scan (@) {
    my %params=@_;
    my $page = $params{page};

    if (!$Database)
    {
        error(gettext("sqlscrape failed, no database"));
    }
    if (!$Transaction_On)
    {
	my $ret = $Database->do("BEGIN TRANSACTION;");
	if (!$ret)
	{
	    error(gettext("sqlscrape failed BEGIN TRANSACTION : $DBI::errstr"));
	}
	$Transaction_On = 1;
    }
    scrape_fields(%params);
    scrape_attachments(%params);
    $Num_Trans++;
    if ($Transaction_On and $Num_Trans > 100)
    {
	my $ret = $Database->do("COMMIT;");
	if (!$ret)
	{
	    error(gettext("sqlscrape failed COMMIT : $DBI::errstr"));
	}
        debug("sqlscrape $Num_Trans transactions committed");
	$Transaction_On = 0;
        $Num_Trans = 0;
    }
} # scan

sub format (@) {
    my %params=@_;
    my $page = $params{page};

    # This is a hack to commit transactions after all scanning is done
    # And to detach from the database because we're done.
    if (!$Database)
    {
        return $params{content};
    }
    if ($Transaction_On)
    {
	my $ret = $Database->do("COMMIT;");
	if (!$ret)
	{
	    error(gettext("sqlscrape failed COMMIT : $DBI::errstr"));
	}
	$Database->disconnect();
	$Transaction_On = 0;
        debug("sqlscrape $Num_Trans transactions committed");
        debug("sqlscrape database disconnected");
    }
    return $params{content};
} # format

# =================================================================
# Private functions

sub scrape_fields {
    my %params=@_;
    my $page = $params{page};

    my @values = ();
    foreach my $fn (@{$config{sqlscrape_fields}})
    {
	my $val = IkiWiki::Plugin::field::field_get_value($fn, $page);
	if (!defined $val)
	{
	    push @values, "NULL";
	}
	elsif (ref $val)
	{
	    $val = join("|", @{$val});
	    $val =~ s/'/''/g; # sql-friendly quotes
	    push @values, "'$val'";
	}
	else
	{
	    $val =~ s/'/''/g; # sql-friendly quotes
	    push @values, "'$val'";
	}
    }

    # Check if the page exists in the table
    # and do an INSERT or UPDATE depending on whether it does.
    # This is faster than REPLACE because it doesn't need
    # to rebuild indexes.
    my $page_exists = get_total_matching(page=>$page, table=>'pagefields');
    my $iquery;
    if ($page_exists)
    {
	$iquery = "UPDATE pagefields SET ";
	for (my $i=0; $i < @values; $i++)
	{
	    $iquery .= sprintf('%s = %s', $config{sqlscrape_fields}->[$i], $values[$i]);
	    if ($i + 1 < @values)
	    {
		$iquery .= ", ";
	    }
	}
	$iquery .= " WHERE page = '$page';";
    }
    else
    {
	$iquery = "INSERT INTO pagefields (page, "
	. join(", ", @{$config{sqlscrape_fields}}) . ") VALUES ('$page', "
	. join(", ", @values) . ");";
    }
    my $ret = $Database->do($iquery);
    if (!$ret)
    {
	error(gettext("sqlscrape failed insert/update '$iquery' : $DBI::errstr"));
    }
} # scrape_fields

sub scrape_attachments {
    my %params=@_;
    my $page = $params{page};

    # This figures out what is "below" this page;
    # the files in the directory associated with this page.
    # Note that this does NOT take account of underlays.

    # This will ignore pages and only deal with selected attachments:
    # EPUB and PDF

    my $srcdir = $config{srcdir};
    my $page_dir = $srcdir . '/' . $page;
    if ($page eq 'index')
    {
	$page_dir = $srcdir;
    }
    if (-d $page_dir) # there is a page directory
    {
	scrape_selected_attachments(%params,
	    page=>$page,
	    page_dir=>$page_dir,
	    match=>'*.epub');
	scrape_selected_attachments(%params,
	    page=>$page,
	    page_dir=>$page_dir,
	    match=>'*.pdf');
    }
    return undef;
} # scrape_attachments

sub scrape_selected_attachments {
    my %params=@_;
    my $page = $params{page};
    my $page_dir = $params{page_dir};
    my $match = $params{match};

    if (-d $page_dir) # there is a page directory
    {
	my $srcdir = $config{srcdir};
	my @files = <${page_dir}/${match}>;
	foreach my $file (@files)
	{
	    if ($file =~ m!$srcdir/(.*)!)
	    {
		my $p = $1;
		if (!pagetype($p))
		{
		    # this is an attachment
		    scrape_fields(page=>$p);
		}
	    }
	}
    }
} # scrape_attachments

sub get_total_matching {
    my %params = @_;
    my $page = $params{page};
    my $table = $params{table};

    my $total_query = "SELECT COUNT(*) FROM $table WHERE page = '$page';";
    
    my $tot_sth = $Database->prepare($total_query);
    if (!$tot_sth)
    {
	debug("Can't prepare query $total_query: $DBI::errstr");
	return 0;
    }
    my $rv = $tot_sth->execute();
    if (!$rv)
    {
	debug("Can't execute query $total_query: $DBI::errstr");
	return 0;
    }
    my $total = 0;
    my @row;
    while (@row = $tot_sth->fetchrow_array)
    {
	$total = $row[0];
    }
    return $total;

} # get_total_matching

1;
