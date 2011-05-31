#!/usr/bin/perl
# Ikiwiki ymlfform plugin. 
# YML-Front-Form-Template
# Use a template to define a form to fill in ymlfront format in a page.
package IkiWiki::Plugin::ymlfform;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "ymlfform",  call => \&getsetup);
	hook(type => "checkconfig", id => "ymlfform", call => \&checkconfig);

	#hook(type => "sessioncgi", id => "ymlfform", call => \&sessioncgi);
	hook(type => "checkcontent", id => "ymlfform", call => \&checkcontent);
	hook(type => "editcontent", id => "ymlfform", call => \&editcontent);
	hook(type => "formbuilder_setup", id => "ymlfform", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "ymlfform", call => \&formbuilder);
}

# ---------------------------------------------------------
# Hooks

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		ymlform_spec => {
			type => 'hash',
			example => '{ "foo/*" => "fooform.yml"}',
			description => 'pagespec => form-definition mapping for ymlforms',
			link => 'ikiwiki/PageSpec',
			safe => 0,
			rebuild => 1,
		},
}

sub checkconfig () {
	$config{ymlform_spec} = {}
		unless defined $config{ymlform_spec};
}

sub sessioncgi ($$) {
    my $cgi=shift;
    my $session=shift;

    my $do = $cgi->param('do');
    if ($do eq 'edit' or $do eq 'blog')
    {
	edit_yml($cgi, $session);
    }
}

sub checkcontent (@) {
    my %params=@_;
    my $page=$params{page};
    my $content=$params{content};
    my $cgi=$params{cgi};
    my $session=$params{session};

    return undef;
}

sub editcontent ($$$) {
    my %params=@_;
    my $content=$params{content};
    my $cgi=$params{cgi};
    my $session=$params{session};

    # now put the ymlfront data back into the editcontent field
    my %ymldata = ();
    foreach my $field ($cgi->param())
    {
	if ($field =~ /^YML_(.*)/i)
	{
	    my $yfn = lc($1);
	    $ymldata{$yfn} = $cgi->param($field);
	}
    }
    if (%ymldata)
    {
	my @delim = @{$config{ymlfront_delim}};
	my $ystr = Dump(\%ymldata);
	$content =<<EOT;
$delim[0]
$ystr
$delim[1]
$content
EOT
	debug("ymlform editcontent:\n=====\n$content\n=====\n");
    }

    return $content;
}

sub formbuilder_setup (@) {
    my %params=@_;

    my $cgi=$params{cgi};
    my $session=$params{session};
    my $form=$params{form};
    my $buttons=$params{buttons};

    # This untaint is safe because we check wiki_file_regexp.
    my ($page)=$form->field('page')=~/$config{wiki_file_regexp}/;
    $page=IkiWiki::possibly_foolish_untaint($page);
    my $do = $cgi->param('do');
    if ($do eq 'blog' or $do eq 'create')
    {
	my ($from)=$form->field('from')=~/$config{wiki_file_regexp}/;
	$from=IkiWiki::possibly_foolish_untaint($from);
	$page = "${from}/${page}";
    }

    my $formspec = get_page_formspec($page);
    if (!$formspec)
    {
	debug("ymlfform: no formspec for $page");
	return;
    }
    foreach my $key (sort keys %{$formspec})
    {
	if ($key eq 'fields')
	{
	    if (ref $formspec->{$key} eq 'ARRAY')
	    {
		foreach my $fn (@{$formspec->{$key}})
		{
		    $form->field(name=>"YML_${fn}", type=>"text", size=>60);
		}
	    }
	    elsif (ref $formspec->{$key} eq 'HASH')
	    {
		foreach my $fn (sort keys %{$formspec->{$key}})
		{
		    $form->field(name=>"YML_${fn}",
				 %{$formspec->{$key}->{$fn}});
		}
	    }
	}
	elsif ($key eq 'required')
	{
	    if (ref $formspec->{$key} eq 'ARRAY')
	    {
		foreach my $fn (@{$formspec->{$key}})
		{
		    $form->field(name=>"YML_${fn}", required=>1);
		}
	    }
	}
	elsif ($key eq 'validate')
	{
	    if (ref $formspec->{$key} eq 'HASH')
	    {
		$form->validate(%{$formspec->{$key}});
	    }
	}
	elsif ($key eq 'template')
	{
	    # set the template
	    $form->template({ IkiWiki::template($formspec->{$key}) });
	}
	else
	{
	}
    }
} # formbuilder_setup

sub formbuilder (@) {
    my %params=@_;
    my $form=$params{form};

    # Return if a YML-form is not defined for this page
    my $page=$form->field("page");
    my $formspec = get_page_formspec($page);
    return if (!defined $formspec or !$formspec);

    # Return if we are editing and there is no content to look at yet
    return if ($form->field("do") eq "edit"
	       && ( !defined $form->field("editcontent")
		    || ! $form->field("editcontent")));

    my $yml = undef;
    my $yml_data = undef;
    # Check if there is any existing YAML content
    if ($form->field("do") eq "edit"
	and $form->field("editcontent"))
    {
	$yml = IkiWiki::Plugin::ymlfront::extract_yml
	    (page=>$page,
	     content=>$form->field("editcontent"));
	if (defined $yml
	    and defined $yml->{yml})
	{
	    $yml_data = IkiWiki::Plugin::ymlfront::parse_yml
		(page=>$page,
		 data=>$yml->{yml});
	}
    }

    foreach my $field ($form->field)
    {
	if ($field =~ /^YML_(.*)/i) {
	    my $yfn = lc($1);
	    if (defined $yml_data
		and defined $yml_data->{$yfn})
	    {
		$form->field(name=>$field, value=>$yml_data->{$yfn});
	    }
	    else # check the CGI parameters
	    {
		my $value = $form->cgi_param($yfn);
		if ($value)
		{
		    $form->field(name=>$field, value=>$value);
		}
	    }
	}
    }
    if (defined $yml)
    {
	# and set the editcontent to the remaining content
	$form->field(name=>"editcontent", value=>$yml->{content});
    }
}

# ---------------------------------------------------------
# Private Functions

# Mostly cargo-culted from IkiWiki::plugin::editpage
sub edit_yml ($$) {
    my $cgi=shift;
    my $session=shift;

    IkiWiki::decode_cgi_utf8($cgi);

    eval {use CGI::FormBuilder};
    error($@) if $@;

    # The untaint is OK (as in editpage) because we're about to pass
    # it to file_pruned anyway
    my $page = $cgi->param('page');
    $page = IkiWiki::possibly_foolish_untaint($page);
    if (! defined $page || ! $page ||
	IkiWiki::file_pruned($page)) {
	error(gettext("bad page name"));
    }
    my $formspec = get_page_formspec($page);
    if (!$formspec)
    {
	return;
    }
    my @buttons=("Save Page", "Preview", "Cancel");
    my $form = CGI::FormBuilder->new
	(
	 charset => 'utf-8',
	 method => 'POST',
	 javascript => 0,
	 params => $cgi,
	 action => $config{cgiurl},
	 header => 0,
	 table => 0,
	 %{$formspec},
	);
    IkiWiki::decode_form_utf8($form);
    IkiWiki::run_hooks(formbuilder_setup => sub {
		       shift->(title => "comment", form => $form, cgi => $cgi,
			       session => $session, buttons => \@buttons);
		       });
    IkiWiki::decode_form_utf8($form);
} # edit_yml

sub get_page_formspec ($) {
    my $page = shift;

    my $formspec = '';
    foreach my $ps (sort keys %{$config{ymlform_spec}})
    {
	if (pagespec_match($page, $ps, location=>$page))
	{
	    $formspec = $config{ymlform_spec}->{$ps};
	    last;
	}
    }
    # If the formspec is a hash, return it;
    # otherwise it is either a YAML file
    # or a HTML::Template file.
    if (ref $formspec eq 'HASH')
    {
	return $formspec;
    }
    if ($formspec)
    {
	my $file;
	if (-f $formspec)
	{
	    $file = $formspec;
	}
	elsif (-f $config{templatedir} . "/" . $formspec)
	{
	    $file = $config{templatedir} . "/" . $formspec;
	}
	if ($file =~ /\.yml$/)
	{
	    eval {use YAML::Any qw(Dump LoadFile);};
	    if ($@)
	    {
		eval {use YAML qw(Dump LoadFile);};
		error($@) if $@;
	    }
	    $formspec = LoadFile($file);
	    return $formspec;
	}
    }
    return undef;
} # get_page_formspec

sub get_yml_data {
    my %params=@_;
    my $page = $params{page};
    my $content = $params{content};

    my $yml_data = undef;
    my $extracted_yml = IkiWiki::Plugin::ymlfront::extract_yml(%params);
    if (defined $extracted_yml
	and defined $extracted_yml->{yml})
    {
	$yml_data = IkiWiki::Plugin::ymlfront::parse_yml
	    (page=>$page,
	     data=>$extracted_yml->{yml});
    }
    elsif ($content =~ qr{
			(\\?)		# 1: escape?
			\[\[(!)		# directive open; 2: prefix
			(ymlfront)	# 3: command
			(		# 4: the parameters..
				\s+	# Must have space if parameters present
				(?:
					(?:[-\w]+=)?		# named parameter key?
					(?:
						""".*?"""	# triple-quoted value
						|
						"[^"]*?"	# single-quoted value
						|
						[^"\s\]]+	# unquoted value
					)
					\s*			# whitespace or end
								# of directive
				)
			*)?		# 0 or more parameters
			\]\]		# directive closed
    }sx)
    {
	my $escape = $1;
	my $prefix = $2;
	my $command = $3;
	my $params = $4;
	# TODO fix this later
    }
} # get_yml_data
1
