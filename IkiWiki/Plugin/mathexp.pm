#!/usr/bin/perl
# Evaluate a math expression
package IkiWiki::Plugin::mathexp;

use warnings;
use strict;
use IkiWiki 3.00;

# -------------------------------------------------------------------
# Import
# -------------------------------------
sub import {
	hook(type => "getsetup", id => "mathexp", call => \&getsetup);
	hook(type => "preprocess", id => "mathexp", call => \&preprocess);
}

# -------------------------------------------------------------------
# Hooks
# -------------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub preprocess (@) {
    my %params=@_;

    my $math = $params{data};
    my $result = eval $math;
    if ($@)
    {
        return "ERROR: $math";
    }
    else
    {
        return "$math = $result";
    }
}


1
