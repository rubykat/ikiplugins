#!/usr/bin/perl
# Form for creating a new page.
package IkiWiki::Plugin::newpage;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "newpage",  call => \&getsetup);
	hook(type => "checkconfig", id => "newpage", call => \&checkconfig);
	hook(type => "pageactions", id => "newpage", call => \&pageactions);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "misc",
		},
}

sub checkconfig () {
}

sub pageactions (@) {
    my %params=@_;
    my $page=$params{page};

    my $cgiurl = $config{cgiurl};
    my $form =<<EOT;
    <form method="get" action="$cgiurl" id="newpageform">
<input type="submit" name="do" value="create" class="button"/>
<input type="hidden" name="from" value="$page"/>
<input type="text" name="page" value="" class="input"/>
</form>
EOT
    return ($form);
}


1
