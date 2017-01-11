#!/usr/bin/perl
package IkiWiki::Plugin::vcard;
use strict;
=head1 NAME

IkiWiki::Plugin::vcard - Produce vcards from page field data.

=head1 VERSION

This describes version B<1.20170111> of IkiWiki::Plugin::vcard

=cut

our $VERSION = '1.20170111';

=head1 DESCRIPTION

Make a report in vCard format from the field values of multiple pages.
Depends on the "field" plugin.

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::field
    vCard
    Encode
    POSIX

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2017 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;
use vCard;
use Encode;
use POSIX qw(ceil);

sub import {
	hook(type => "getsetup", id => "vcard", call => \&getsetup);
	hook(type => "preprocess", id => "vcard", call => \&preprocess);

	IkiWiki::loadplugin("field");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
    my %params=@_;

    my $this_page = $params{page};
    my $dest_page = $params{destpage};
    my $pages = (defined $params{pages} ? $params{pages} : '*');
    $pages =~ s/\{\{\$page\}\}/$this_page/g;

    my $deptype=deptype($params{quick} ? 'presence' : 'content');

    my @matching_pages;
    my @trailpages = ();
    # Don't add the dependencies yet because
    # the results could be further filtered below.
    if ($params{pagenames})
    {
	@matching_pages =
	    map { bestlink($params{page}, $_) } split ' ', $params{pagenames};
	# Because we used pagenames, we have to sort the pages ourselves.
	# This code is cribbed from pagespec_match_list
	if ($params{sort})
	{
	    my $sort=IkiWiki::sortspec_translate($params{sort},
						 $params{reverse});
	    @matching_pages=IkiWiki::SortSpec::sort_pages($sort,
							  @matching_pages);
	}
    }
    else
    {
	@matching_pages = pagespec_match_list($params{destpage}, $pages,
					      %params,
					      num=>$params{count},
					      deptype => 0);
    }

    # Only add dependencies IF we found matches
    if ($#matching_pages > 0)
    {
	foreach my $mp (@matching_pages)
	{
	    add_depends($dest_page, $mp, $deptype);
	}
    }

    # build up the report
    #
    my @report = ();

    my $start = ($params{start} ? $params{start} : 0);
    my $stop = ($params{count}
        ? (($start + $params{count}) <= @matching_pages
            ? $start + $params{count}
            : scalar @matching_pages
        )
        : scalar @matching_pages);
    my $output = '';
    $output = build_report(%params,
        start=>$start,
        stop=>$stop,
        matching_pages=>\@matching_pages,
    );

    return $output;
} # preprocess

# -------------------------------------------------------------------
# Private Functions
# -------------------------------------

sub build_report (@) {
    my %params = (
		start=>0,
		@_
	       );

    my @matching_pages = @{$params{matching_pages}};
    my $destpage_baseurl = IkiWiki::baseurl($params{destpage});
    my @report = ();

    my $start = $params{start};
    my $stop = $params{stop};
    my @header_fields = ($params{headers} ? split(' ', $params{headers}) : ());
    my @prev_headers = ();
    for (my $j=0; $j < @header_fields; $j++)
    {
	$prev_headers[$j] = '';
    }
    for (my $i=$start; $i < $stop and $i < @matching_pages; $i++)
    {
	my $page = $matching_pages[$i];
	my $prev_page = ($i > 0 ? $matching_pages[$i-1] : '');
	my $next_page = ($i < $#matching_pages ? $matching_pages[$i+1] : '');
	my $first = ($i == $start);
	my $last = (($i == ($stop - 1)) or ($i == $#matching_pages));
	my @header_values = ();
	foreach my $fn (@header_fields)
	{
	    my $val =
		IkiWiki::Plugin::field::field_get_value($fn, $page);
	    $val = '' if !defined $val;
	    $val = join(' ', @{$val}) if ref $val eq 'ARRAY';
	    push @header_values, $val;
	}
	my $rowr = do_one_vcard(
	    %params,
	    page=>$page,
	    destpage_baseurl=>$destpage_baseurl,
	    recno=>$i,
	    prev_page=>$prev_page,
	    next_page=>$next_page,
	    destpage=>$params{destpage},
	    first=>$first,
	    last=>$last,
	    headers=>\@header_values,
	    prev_headers=>\@prev_headers,
	);
	for (my $j=0; $j < @header_fields; $j++)
	{
	    if ($header_values[$j] ne $prev_headers[$j])
	    {
		$prev_headers[$j] = $header_values[$j];
	    }
	}
	push @report, $rowr;
    }

    if (! @report) {
	return '';
    } 
    my $output = join('', @report);

    return $output;
} # build_report

sub do_one_vcard (@) {
    my %params=@_;

    $params{included}=($params{page} ne $params{destpage});

    my $vcard = vCard->new;

    # build a hash of data which vCard understands
    my $firstname = IkiWiki::Plugin::field::field_get_value('firstname', $params{page});
    my $firstname2 = IkiWiki::Plugin::field::field_get_value('firstname2', $params{page});
    my $lastname = IkiWiki::Plugin::field::field_get_value('lastname', $params{page});
    my $title = IkiWiki::Plugin::field::field_get_value('title', $params{page});
    my $nickname = IkiWiki::Plugin::field::field_get_value('nickname', $params{page});
    my $organisation = IkiWiki::Plugin::field::field_get_value('organisation', $params{page});
    my $birthdate = IkiWiki::Plugin::field::field_get_value('birthdate', $params{page});
    my $addresses = IkiWiki::Plugin::field::field_get_value('addresses', $params{page});
    my $phones = IkiWiki::Plugin::field::field_get_value('phones', $params{page});
    my $emails = IkiWiki::Plugin::field::field_get_value('emails', $params{page});
    my $urls = IkiWiki::Plugin::field::field_get_value('urls', $params{page});
    my %person = ();
    $person{given_names} = [$firstname];
    push @{$person{given_names}} if $firstname2;
    $person{family_names} = [$lastname];
    $person{full_name} = $title;
    $person{title} = $nickname;
    $person{photo} = '';
    $person{version} = '2.1';
    if (defined $phones and $phones)
    {
        $person{phones} = [];
        foreach my $val ((ref $phones eq 'ARRAY' ? @{$phones} : ($phones)))
        {
            if ($val)
            {
                my $type = 'HOME';
                my $v = $val;
                if ($val =~ /(cell|work|home)\s*(.*)/i)
                {
                    $type = uc($1);
                    $v = $2;
                }
                if ($v)
                {
                    push @{$person{phones}}, {type => [$type], number => $v};
                }
            }
        }
    }
    if (defined $addresses and $addresses)
    {
        $person{addresses} = [];
        foreach my $val ((ref $addresses eq 'ARRAY' ? @{$addresses} : ($addresses)))
        {
            if ($val)
            {
                my $type = 'HOME';
                my $vline = $val;
                if ($val =~ /(work|home)\s*(.*)/i)
                {
                    $type = uc($1);
                    $vline = $2;
                }
                my %data = ();
                if ($vline =~ /^(\d\d*|\d\d*\/\d\d*)\s+(\w+)\s+(Rd|St|Ct|Crt|Street|Road|Court)\s+(\w+)\s+(\w+)\s*(\d+)?\s*(\w+)/is)
                {
                    $data{pobox} = $1;
                    $data{street} = $2 . ' ' . $3;
                    $data{city} = $4;
                    $data{region} = $5;
                    $data{post_code} = $6;
                    $data{country} = $7;
                    warn "FOUND1 $vline\n";
                }
                elsif ($vline =~ /^(PO Box\s+\d\d*)\s+(\w+)\s+(\w+)\s*(\d+)?\s*(\w+)/is)
                {
                    $data{pobox} = $1;
                    $data{street} = '';
                    $data{city} = $2;
                    $data{region} = $3;
                    $data{post_code} = $4;
                    $data{country} = $5;
                    warn "FOUND2 $vline\n";
                }
                if (%data)
                {
                    push @{$person{addresses}}, {type => [$type], %data};
                }
            }
        }
    }
    if (defined $emails and $emails)
    {
        $person{email_addresses} = [];
        foreach my $val ((ref $emails eq 'ARRAY' ? @{$emails} : ($emails)))
        {
            if ($val)
            {
                my $type = 'HOME';
                my $v = $val;
                if ($val =~ /(work|home)\s*(.*)/i)
                {
                    $type = uc($1);
                    $v = $2;
                }
                if ($v)
                {
                    push @{$person{email_addresses}}, {type => [$type], address => $v};
                }
            }
        }
    }
    $vcard->load_hashref(\%person);

    my $output = $vcard->as_string;

    return IkiWiki::preprocess($params{page}, $params{destpage},
			       IkiWiki::filter($params{page}, $params{destpage},
					       $output), 0);

} # do_one_vcard

1;
