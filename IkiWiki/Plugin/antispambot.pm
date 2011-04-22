#!/usr/bin/perl
# Ikiwiki antispambot plugin.
# Substitute field values in the content of the page.
package IkiWiki::Plugin::antispambot;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "antispambot",  call => \&getsetup);
	hook(type => "sanitize", id => "antispambot", call => \&sanitize);
}

#---------------------------------------------------------------
# Hooks
# --------------------------------

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		antispambot_at_img => {
			type => "string",
			example => "http://www.example.com/images/at.png",
			description => "URL of an image to replace the @ with",
			safe => 0,
			rebuild => undef,
		},
}

sub sanitize (@) {
    my %params=@_;
    my $page=$params{page};
    my $destpage=$params{destpage};

    my $page_file=$pagesources{$page};
    my $page_type=pagetype($page_file);
    if (defined $page_type)
    {
	# substitute mailto: links
	$params{content} =~ s/<a[^>]+href\s*=\s*['"]mailto:([^'"]+)['"][^>]*>([^<]+)<\/a>/process_mailto($1,$2,$page,$destpage)/eg;
    }

    return $params{content};
}

#---------------------------------------------------------------
# Private functions
# --------------------------------
sub process_mailto ($$$) {
    my $email = shift;
    my $label = shift;
    my $page = shift;
    my $destpage = shift;

    my $user;
    my $domain;
    if ($email =~ /\b([\w._%+-]+)\@([\w.-]+\.[a-zA-Z]{2,6})\b/)
    {
	$user = $1;
	$domain = $2;
    }
    else
    {
	return $email;
    }
    my $at = ($config{antispambot_at_img}
	      ? "<img src='$config{antispambot_at_img}' alt='AT'/>"
	      : ' at '
	     );
    my $spell_domain = $domain;
    $spell_domain =~ s/\./\&\#8901;/g;
    if ($email eq $label)
    {
	return "&lt;${user}${at}${spell_domain}&gt;";
    }
    else
    {
	return "$label &lt;${user}${at}${spell_domain}&gt;";
    }
} # get_field_value

1;
