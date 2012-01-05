#!/usr/bin/perl
package IkiWiki::Plugin::kalbum;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::kalbum - kat's album plugin

=head1 VERSION

This describes version B<1.20120105> of IkiWiki::Plugin::kalbum

=cut

our $VERSION = '1.20120105';

=head1 DESCRIPTION

Creates an album from a set of images; generates thumbnails,
image-pages, and multiple index-pages for an album.

See doc/plugin/contrib/kalbum.mdwn for documentation.

=head1 PREREQUISITES

    IkiWiki
    File::Basename
    POSIX
    IkiWiki::Plugin::field
    IkiWiki::Plugin::report

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009-2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;
use File::Basename;
use POSIX qw(ceil);

sub import {
	hook(type => "getsetup", id => "kalbum",  call => \&getsetup);
	hook(type => "checkconfig", id => "kalbum", call => \&checkconfig);
	hook(type => "preprocess", id => "kalbum", call => \&preprocess, scan=>1, last=>1);
	hook(type => "formbuilder_setup", id => "kalbum", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "kalbum", call => \&formbuilder);
	hook(type => "sanitize", id => "kalbum", call => \&sanitize);
	hook(type => "format", id => "kalbum", call => \&format);

	IkiWiki::loadplugin("field");
	IkiWiki::loadplugin("ftemplate");
	IkiWiki::loadplugin("report");

	IkiWiki::Plugin::field::field_register(id=>'kalbum',
					       get_value=>\&kalbum_get_value);
}

#------------------------------------------------------------------
# Hooks
#------------------------------------------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		kalbum_image_regexp => {
			type => "string",
			example => '\.(:?jpg|png|gif)',
			description => "regexp for images",
			safe => 0,
			rebuild => 1,
		},
		kalbum_jquery_media_js => {
			type => "string",
			example => '/include/jquery.media.js',
			description => "url for jquery media plugin",
			safe => 0,
			rebuild => 1,
		},
		kalbum_thumb_folder => {
			type => "string",
			example => '/images/folder.png',
			description => "page-name of generic folder image",
			safe => 0,
			rebuild => 1,
		},
		kalbum_thumb_other => {
			type => "string",
			example => '/images/video.png',
			description => "page-name of generic non-video image",
			safe => 0,
			rebuild => 1,
		},
		kalbum_long_caption => {
			type => "string",
			example => '%ImageSize% %Comment% %caption%',
			description => "default format for a long caption",
			safe => 0,
			rebuild => 1,
		},
		kalbum_short_caption => {
			type => "string",
			example => '%ImageSize% %caption%',
			description => "default format for a short caption",
			safe => 0,
			rebuild => 1,
		},
} # getsetup

sub checkconfig () {
    if (!exists $config{kalbum_image_regexp}
	or !defined $config{kalbum_image_regexp})
    {
	$config{kalbum_image_regexp} = qr/\.(:?jpg|png|gif)$/io;
    }
    if (!exists $config{kalbum_default_filespec}
	or !defined $config{kalbum_default_filespec})
    {
	$config{kalbum_default_filespec} = '(*.jpg or *.png or *.gif)';
    }
    if (!exists $config{kalbum_long_caption}
	or !defined $config{kalbum_long_caption})
    {
	$config{kalbum_long_caption} = '%caption%';
    }
    if (!exists $config{kalbum_short_caption}
	or !defined $config{kalbum_short_caption})
    {
	$config{kalbum_short_caption} = '%caption%';
    }
} # checkconfig

sub preprocess (@) {
    my %params=@_;
    my $page = $params{page};

    my $scanning=! defined wantarray;
    if ($scanning)
    {
	return preprocess_scan(%params);
    }
    else
    {
	return preprocess_do(%params);
    }
} # preprocess

sub formbuilder_setup (@) {
    my %params=@_;
    my $form=$params{form};
    my $q=$params{cgi};

    if (defined $form->field("do") && ($form->field("do") eq "edit" ||
				       $form->field("do") eq "create"))
    {
	# Add caption field.
	$form->field(name => 'caption',
		     type => 'text',
		     size=> 65);
	# These buttons are not put in the usual place, so
	# are not added to the normal formbuilder button list.
	$form->tmpl_param("field-addcaption" => '<input name="_submit" type="submit" value="Add Caption" />');
    }
} # formbuilder_setup

sub formbuilder (@) {
    my %params=@_;
    my $form=$params{form};
    my $q=$params{cgi};

    return if ! defined $form->field("do") || ($form->field("do") ne "edit" && $form->field("do") ne "create") ;

    my $caption=Encode::decode_utf8($q->param('caption'));
    if (defined $caption
	and $form->submitted eq "Add Caption")
    {
	my $page=quotemeta(Encode::decode_utf8($q->param("page")));
	my $add="";
	foreach my $f ($q->param("attachment_select")) {
	    $f=Encode::decode_utf8($f);
	    #$f=~s/^$page\///;
	    $add.=<<EOT;
[[!kalbum image="$f" caption="$caption"]]
EOT
	}
	$form->field(name => 'editcontent',
		     value => $form->field('editcontent')."\n\n".$add,
		     force => 1) if length $add;
    }
} # formbuilder

sub sanitize (@) {
    my %params=@_;
    my $page = $params{page};
    my $content = $params{content};

    if (exists $pagestate{$page}{kalbum}{page_in_album_params}
	and defined $pagestate{$page}{kalbum}{page_in_album_params}
	and $page eq $params{destpage})
    {
	my %page_params = %{$pagestate{$page}{kalbum}{page_in_album_params}};
	my $caption = get_caption(%page_params);
	my $img_basename = IkiWiki::basename($page);
	my $id = ($page_params{image_template}
	    ? $page_params{image_template}
	    : "kalbum_image"),
	my $template;
	eval {
	    # Do this in an eval because it might fail
	    # if the template isn't a page in the wiki
	    $template=template_depends($id, $params{page},
		blind_cache => 1);
	};
	if (! $template) {
	    # look for .tmpl template (in global templates dir)
	    eval {
		$template=template("$id.tmpl",
		    blind_cache => 1);
	    };
	    if ($@) {
		error gettext("failed to process template $id.tmpl:")." $@";
	    }
	    if (! $template) {
		error sprintf(gettext("%s not found"),
		    htmllink($params{page}, $params{page},
			"/templates/$id"));
	    }
	}
	IkiWiki::Plugin::field::field_set_template_values($template,
	    $params{page},
	    %params,
	    %page_params,
	    destpage=>'',
	    image=>$page,
	    image_basename=>$img_basename,
	    caption=>$caption,
	    is_image=>0,
	    is_page=>1,
	    page_content=>$content,
	);
	my $pout = $template->output;

	if (!$pout)
	{
	    $pout=<<EOT;
ftemplate failed for $page
image_basename=$img_basename
prev_item=$page_params{prev_item}
next_item=$page_params{next_item}
EOT
	}
	$content = IkiWiki::linkify($params{page}, $params{page}, $pout);
    }
    return $content;
} # sanitize

sub format (@) {
    my %params=@_;

    my $page = $params{page};

    my $page_file=$pagesources{$page} || return $params{content};
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return $params{content};
    }
    if (!exists $pagestate{$page}{kalbum}{size}
	or !defined $pagestate{$page}{kalbum}{size})
    {
	# not an album page
	return $params{content};
    }

    # add styles for album
    if (! ($params{content}=~s!(<head[^>]*>\s*)!$1.include_styles($params{page})!em))
    {
	# no <head> tag, probably in preview mode
	return $params{content};
    }
    return $params{content};
} # format

#------------------------------------------------------------------
# Private Functions
#------------------------------------------------------------------

sub preprocess_scan (@) {
    my %params=@_;
    my $page = $params{page};

    my $size = ($params{size} ? $params{size} : "100x100");

    $pagestate{$page}{kalbum}{size} = $size;
    # process captions and thumbnails
    if ($params{image})
    {
	if ($params{caption})
	{
	    $pagestate{$params{image}}{kalbum}{caption} = $params{caption};
	}
	if ($params{thumbnail})
	{
	    calculate_image_data(%params,
			   item=>$params{image},
			   size=>$size);
	}
	return '';
    }

    # Is album definition
    my $pagespec = ($params{pages}
		    ? $params{pages}
		    : "${page}/* and !${page}/*/*"
		   );
    $pagespec =~ s/{{\$page}}/$page/g;

    my $deptype=deptype('presence');

    my @items =
    pagespec_match_list($page, $pagespec,
	location=>$page,
	deptype => $deptype,
    );
    foreach my $item (@items)
    {
	calculate_image_data(%params,
		       size=>$size,
		       item=>$item);
    }
} # preprocess_scan

sub preprocess_do (@) {
    my %params=@_;
    my $page = $params{page};

    # the "image" info is only checked when scanning
    if ($params{image})
    {
	return '';
    }
    my $size = ($params{size} ? $params{size} : "100x100");
    my $pagespec = ($params{pages}
		    ? $params{pages}
		    : "${page}/* and !${page}/*/*"
		   );
    my $deptype=deptype('presence');

    my @items =
    pagespec_match_list($page, $pagespec,
	location=>$page,
	deptype => $deptype,
    );

    eval {use Sort::Naturally};
    if ($@)
    {
	@items = sort(@items);
    }
    else
    {
	@items = nsort(@items);
    }
    my $start = 0;
    my $stop = $#items;
    for (my $i=$start; $i <= $stop and $i < @items; $i++)
    {
	my $item = $items[$i];
	my $prev_item = ($i > 0
	    ? $items[$i-1]
	    : $items[$stop]);
	my $next_item = ($i < $#items
	    ? $items[$i+1]
	    : $items[$start]);
	my $first = ($i == $start);
	my $last = ($i == $stop);
	make_thumbnail(%params,
		       size=>$size,
		       item=>$item);
	make_image_page(%params,
	    image=>$item,
	    album=>$page,
	    prev_item=>$prev_item,
	    prev_page_url=>img_page_url($prev_item, $item),
	    prev_thumb_url=>kalbum_get_value('thumb_url', $prev_item),
	    next_item=>$next_item,
	    next_page_url=>img_page_url($next_item, $item),
	    next_thumb_url=>kalbum_get_value('thumb_url', $next_item),
	    first=>$first,
	    last=>$last,
	);
    }

    my $out = '';
    if (@items)
    {
	my $basename = IkiWiki::basename($page);
	$out .= make_index_pages(%params,
	    template=>($params{album_template}
		? $params{album_template}
		: "kalbum"),
	    report_id=>($params{report_id}
		? $params{report_id}
		: $basename),
	    albumdesc=>$params{albumdesc},
	    items => \@items,
	);
    }
    return $out;
} # preprocess_do

sub make_image_page {
    my %params=@_;
    my $image = $params{image};

    # this could be a page and not an image
    if (is_page($image)) {
	# this is an actual page
	# remember this page needs altering later
	$pagestate{$image}{kalbum}{page_in_album_params} = \%params;
    }
    else
    {
	create_image_page(%params);
    }

} # make_image_page

sub create_image_page {
    my %params=@_;
    my $image = $params{image};

    # retrieve new pagename
    my $new_page = $pagestate{$image}{kalbum}{image_page};
    my $target = $pagestate{$image}{kalbum}{image_page_target};

    my $is_image = ($image =~ $config{kalbum_image_regexp});
    my $img_basename = IkiWiki::basename($image);
    my $album_basename = IkiWiki::basename($params{album});
    my $id = ($params{image_template}
	? $params{image_template}
	: "kalbum_image"),
    my $template;
    eval {
	# Do this in an eval because it might fail
	# if the template isn't a page in the wiki
	$template=template_depends($id, $params{page},
	    blind_cache => 1);
    };
    if (! $template) {
	# look for .tmpl template (in global templates dir)
	eval {
	    $template=template("$id.tmpl",
		blind_cache => 1);
	};
	if ($@) {
	    error gettext("failed to process template $id.tmpl:")." $@";
	}
	if (! $template) {
	    error sprintf(gettext("%s not found"),
		htmllink($params{page}, $params{page},
		    "/templates/$id"));
	}
    }
    $pagestate{$image}{kalbum}{img_page_url} = img_page_url($image, $params{album});
    $pagestate{$image}{kalbum}{title} = pagetitle(basename($new_page));

    my %itemvals = %{$pagestate{$image}{kalbum}};

    IkiWiki::Plugin::field::field_set_template_values($template,
	$params{page},
	%params,
	%itemvals,
	image=>$image,
	image_basename=>$img_basename,
	album_basename=>$album_basename,
	is_image=>$is_image,
    );
    my $pout = $template->output;

    if (!$pout)
    {
	$pout=<<EOT;
ftemplate failed for $image
image_basename=$img_basename
prev_item=$params{prev_item}
next_item=$params{next_item}
EOT
    }

    # will render file
    will_render($params{page}, $target);
    my $rep = IkiWiki::linkify($params{page}, $new_page, $pout);

    # render as a simple page
    $rep = IkiWiki::Plugin::report::render_simple_page(%params,
			      new_page=>$new_page,
			      content=>$rep);
    writefile($target, $config{destdir}, $rep);
} # create_image_page

sub make_index_pages {
    my %params=@_;
    my $template_id = $params{template};
    my $report_id = $params{report_id};
    my $albumdesc = $params{albumdesc};
    my @items = @{$params{items}};

    my $template;
    eval {
	# Do this in an eval because it might fail
	# if the template isn't a page in the wiki
	$template=template_depends($template_id, $params{page},
	    blind_cache => 1);
    };
    if (! $template) {
	# look for .tmpl template (in global templates dir)
	eval {
	    $template=template("$template_id.tmpl",
		blind_cache => 1);
	};
	if ($@) {
	    error gettext("failed to process template $template_id.tmpl:")." $@";
	}
	if (! $template) {
	    error sprintf(gettext("%s not found"),
		htmllink($params{page}, $params{page},
		    "/templates/$template_id"));
	}
    }

    my $start = ($params{start} ? $params{start} : 0);
    my $stop = ($params{count}
	? (($start + $params{count}) <= @items
	    ? $start + $params{count}
	    : scalar @items
	)
	: scalar @items);
    my $output = '';
    my $num_pages = 1;
    if ($params{per_page})
    {
	my $num_recs = scalar @items;
	$num_pages = ceil($num_recs / $params{per_page});
    }
    # Don't do pagination
    # - when there's only one page
    # - on included pages
    if (($num_pages <= 1)
	or ($params{page} ne $params{destpage}))
    {
	$output = make_single_index(%params,
			       start=>$start,
			       stop=>$stop,
			       items=>\@items,
			       template=>$template,
			      );
    }
    else
    {
	$output = multi_page_index(%params,
				    num_pages=>$num_pages,
				    start=>$start,
				    stop=>$stop,
				    items=>\@items,
				    template=>$template,
				   );
    }

    return $output;
} # make_index_pages

sub make_single_index {
    my %params=@_;

    my $template = $params{template};
    my $report_id = $params{report_id};
    my $albumdesc = $params{albumdesc};
    my @items = @{$params{items}};

    my $start = $params{start};
    my $stop = $params{stop};
    my $out = '';
    for (my $i = $start; $i <= $stop and $i < @items; $i++)
    {
	my $item = $items[$i];
	my $first = ($i == $start);
	my $last = ($i == $stop or $i == $#items);
	my %itemvals = %{$pagestate{$item}{kalbum}};

	$template->clear_params();
	IkiWiki::Plugin::field::field_set_template_values($template,
	    $item,
	    %params,
	);
	$template->param(image=>$item);
	$template->param(first=>$first);
	$template->param(last=>$last);
	$template->param(album=>$params{page});
	$template->param(img_page_url=>img_page_url($item, $params{page}));
	$template->param(%itemvals);

	if (defined $pagestate{$item}{kalbum}{thumb_link})
	{
	    my $thumb_url=urlto($pagestate{$item}{kalbum}{thumb_link}, $params{page});
	    if ($config{usedirs})
	    {
		$thumb_url =~ s!/$!!;
	    }
	    $template->param(thumb_url=>$thumb_url);
	}

	$out .= $template->output;
    }
    $out = IkiWiki::linkify($params{page}, $params{page}, $out) if $out;

    return $out;
} # make_single_index

# Do a multi-page index.
# This assumes that this is not an inlined page.
sub multi_page_index (@) {
    my %params = (
		start=>0,
		@_
	       );

    my @items = @{$params{items}};
    my $template = $params{template};
    my $num_pages = $params{num_pages};
    my $first_page_is_index = $params{first_page_is_index};
    my $report_title = ($params{report_title}
			? sprintf("<h1>%s</h1>", $params{report_title})
			: ''
		       );

    my $first_page_out = '';
    for (my $pind = 0; $pind < $num_pages; $pind++)
    {
	my $page_title = ($pind == 0 ? '' : $report_title);
	my $rep_links = IkiWiki::Plugin::report::create_page_links(%params,
					  num_pages=>$num_pages,
					  cur_page=>$pind,
					  first_page_is_index=>$first_page_is_index);
	my $start_at = $params{start} + ($pind * $params{per_page});
	my $end_at = $params{start} + (($pind + 1) * $params{per_page});
	my $pout = make_single_index(%params,
			       start=>$start_at,
			       stop=>$end_at,
			       items=>\@items,
			       template=>$template,
			      );
	$pout =<<EOT;
<div class="report">
$page_title
$rep_links
$pout
$rep_links
</div>
EOT
	if ($pind == 0 and !$first_page_is_index)
	{
	    $first_page_out = $pout;
	}
	else
	{
	    my $new_page = sprintf("%s_%d",
				   ($params{report_id}
				    ? $params{report_id} : 'report'),
				   $pind + 1);
	    my $target = targetpage($params{page}, $config{htmlext}, $new_page);
	    will_render($params{page}, $target);
	    my $rep = IkiWiki::linkify($params{page}, $new_page, $pout);

	    # render as a simple page
	    $rep = IkiWiki::Plugin::report::render_simple_page(%params,
				      new_page=>$new_page,
				      content=>$rep);
	    writefile($target, $config{destdir}, $rep);
	}
    }
    if ($first_page_is_index)
    {
	$first_page_out = IkiWiki::Plugin::report::create_page_links(%params,
					    num_pages=>$num_pages,
					    cur_page=>-1,
					    first_page_is_index=>$first_page_is_index);
    }

    return $first_page_out;
} # multi_page_report

sub calculate_image_data {
    my %params=@_;
    my $item = $params{item};
    my $size = $params{size};

    my $is_page = is_page($item);
    my $is_image = ($item =~ $config{kalbum_image_regexp});

    my $thumb_name = '';
    my $thumb_src = '';
    my $outfile = '';
    my $thumb_link = '';
    my $thumb_url = '';
    my $basename = IkiWiki::basename($item);

    # figure out the data for the thumbnail and remember it
    add_link($params{page}, $item);
    add_depends($params{page}, $item);

    $pagestate{$item}{kalbum}{image_basename} = $basename;

    # find the name of the image-page
    if ($is_page)
    {
	# already is a page
	$pagestate{$item}{kalbum}{image_page} = $item;
	$pagestate{$item}{kalbum}{image_page_abs_url} = IkiWiki::urlto($item);
	$pagestate{$item}{kalbum}{image_page_bn_wext} = IkiWiki::basename($item)
	. ($config{usedirs} ? '/' : '.' . $config{htmlext});
    }
    else
    {
	my $image_page = $item;
	$image_page =~ s{\.\w+$}{};
	$pagestate{$item}{kalbum}{image_page} = $image_page;
	$pagestate{$item}{kalbum}{image_page_bn_wext} = IkiWiki::basename($image_page) . '.' . $config{htmlext};
	my $image_page_dest = $image_page . '.' . $config{htmlext};
	$pagestate{$item}{kalbum}{image_page_dest} = $image_page_dest;
	$pagestate{$item}{kalbum}{image_page_target} = '/' . $image_page_dest;
	$pagestate{$item}{kalbum}{image_page_abs_url} = IkiWiki::urlto($image_page_dest);
    }

    # Find the name for the thumbnail
    if ($is_page)
    {
	$thumb_name = "${basename}_${size}.jpg";
    }
    else
    {
	if ($basename =~ /(.*)\.\w+$/)
	{
	    $thumb_name = "${1}_${size}.jpg";
	}
	else
	{
	    $thumb_name = "${basename}_${size}.jpg";
	}
    }
    $pagestate{$item}{kalbum}{thumb_name} = $thumb_name;

    # Find the source file for the thumbnail.
    # This can be a specified thumbnail image,
    # the image itself if the item is an image,
    # a generic "folder" thumbnail if the item is a page,
    # or a generic "other" thumbnail if the item is neither an image nor a page.
    if ($params{thumbnail})
    {
	$thumb_src = srcfile($params{thumbnail}, 1);
    }
    elsif ($is_page)
    {
	if ($config{kalbum_thumb_folder})
	{
	    $thumb_src = srcfile($config{kalbum_thumb_folder}, 1);
	    if (! defined $thumb_src) {
		# not an error, but we aren't going to be making a thumbnail
		return;
	    }
	}
    }
    elsif ($is_image)
    {
	$thumb_src = srcfile($item, 1);
    }
    else
    {
	$thumb_src = srcfile($config{kalbum_thumb_other}, 1);
	if (! defined $thumb_src) {
	    # not an error, but we aren't going to be making a thumbnail
	    return;
	}
    }
    $pagestate{$item}{kalbum}{thumb_src} = $thumb_src;

    # Figure out what directory the thumbnail will go into
    my $dir;
    if ($params{is_dir} or is_page($item))
    {
	$dir = $item;
    }
    else
    {
	$item =~ m{(.*)/\w+\.\w+$};
	$dir = $1;
    }
    $outfile = "$config{destdir}/$dir/tn/$thumb_name";
    $thumb_link = "$dir/tn/$thumb_name";
    $pagestate{$item}{kalbum}{outfile} = $outfile;
    $pagestate{$item}{kalbum}{thumb_link} = $thumb_link;
    $pagestate{$item}{kalbum}{render_thumb} = $thumb_link;

    my $vals = kalbum_get_values(%params, page=>$item);
    while (my ($key, $value) = each %{$vals})
    {
	$pagestate{$item}{kalbum}{$key} = $value;
    }

} # calculate_image_data

sub make_thumbnail {
    my %params=@_;
    my $item = $params{item};
    my $size = $params{size};

    # if we don't have a thumb_src
    # then we aren't going to be making a thumbnail - bye!
    if (!exists $pagestate{$item}{kalbum}{thumb_src})
    {
	return;
    }

    my $is_page = is_page($item);
    my $is_image = ($item =~ $config{kalbum_image_regexp});

    my $thumb_name = '';
    my $thumb_src = '';
    my $outfile = '';
    my $thumb_link = '';
    my $thumb_url = '';
    my $basename = IkiWiki::basename($item);

    $thumb_name = $pagestate{$item}{kalbum}{thumb_name};
    $thumb_src = $pagestate{$item}{kalbum}{thumb_src};
    $outfile = $pagestate{$item}{kalbum}{outfile};
    $thumb_link = $pagestate{$item}{kalbum}{thumb_link};
    $thumb_url = $pagestate{$item}{kalbum}{thumb_url};
    will_render($params{page}, $pagestate{$item}{kalbum}{render_thumb})
	if $pagestate{$item}{kalbum}{render_thumb};

    if ($params{preview})
    {
	$thumb_url="$config{url}/$thumb_link";
    }

    # only read the image if we need to make a thumbnail
    if (!(-e $outfile && (-M $thumb_src >= -M $outfile)))
    {
	eval {use Image::Magick};
	error gettext("Image::Magick is not installed") if $@;
	my $im = Image::Magick->new;
	my $r = $im->Read($thumb_src);
	error sprintf(gettext("failed to read %s: %s"), $thumb_src, $r) if $r;

	# calculate width and height of thumbnail display
	$params{size} =~ /(\d+)x(\d+)/;
	my $thumb_width = $1;
	my $thumb_height = $2;
	my $pixelcount = $thumb_width * $thumb_height;

	my $x = $im->Get("width");
	my $y = $im->Get("height");
	if (!$x or !$y)
	{
	    error gettext("dimensions of $item undefined");
	}

	my $pixels = $x * $y;
	my $newx = int($x / (sqrt($x * $y) / sqrt($pixelcount)));
	my $newy = int($y / (sqrt($x * $y) / sqrt($pixelcount)));
	my $newpix = $newx * $newy;

	$r = $im->Resize(geometry => "${newx}x${newy}");
	error sprintf(gettext("failed to resize: %s"), $r) if $r;

	# don't actually write resized file in preview mode;
	# rely on width and height settings
	if (! $params{preview}) {
	    my @blob = $im->ImageToBlob();
	    writefile($thumb_link, $config{destdir}, $blob[0], 1);
	}
    }
} # make_thumbnail

sub kalbum_get_values (@) {
    my %params=@_;

    my %values = ();
    foreach my $fn (qw(short_caption caption is_image))
    {
	$values{$fn} = kalbum_get_value($fn, $params{page});
    }
    return \%values;
} # kalbum_get_values

sub img_page_url ($;$) {
    my $page = shift;
    my $from_page = shift;

    return undef unless defined $page;
    return undef unless defined $from_page;
    my $page_file=$pagesources{$page} || return undef;
    my $page_type=pagetype($page_file);
    my $from_page_file=$pagesources{$from_page} || return undef;
    my $from_page_type=pagetype($from_page_file);

    my $url;
    if ($page_type and $from_page_type)
    {
	$url = IkiWiki::urlto($page, $from_page);
    }
    elsif (!$page_type and $from_page_type)
    {
	my $use_page = $pagestate{$page}{kalbum}{image_page_dest};
	$url = IkiWiki::urlto($use_page, $from_page);
	$url =~ s!($config{htmlext})/$!$1!;
    }
    elsif ($page_type and !$from_page_type)
    {
	my $use_from_page = $pagestate{$from_page}{kalbum}{image_page};
	$url = IkiWiki::urlto($page, $use_from_page);
	$url =~ s!^\.\./!./!;
    }
    elsif (!$page_type and !$from_page_type)
    {
	my $use_page = $pagestate{$page}{kalbum}{image_page_dest};
	my $use_from_page = $pagestate{$from_page}{kalbum}{image_page};
	$url = IkiWiki::urlto($use_page, $use_from_page);
	$url =~ s!^\.\./!!;
	$url =~ s!($config{htmlext})/$!$1!;
    }

    return $url;
} # img_page_url

sub kalbum_get_value ($$) {
    my $field_name = shift;
    my $page = shift;

    if ($field_name eq 'short_caption')
    {
	return get_caption(image=>$page,
			   format=>$config{kalbum_short_caption});
    }
    elsif ($field_name eq 'caption')
    {
	return get_caption(image=>$page);
    }
    elsif ($field_name eq 'is_image')
    {
	my $is_image = ($page =~ $config{kalbum_image_regexp});
	return $is_image;
    }
    return undef;
} # kalbum_get_value

sub get_caption {
    my %params=@_;

    my $image = $params{image};
    
    eval {use Image::ExifTool};
    error gettext("Image::ExifTool is not installed") if $@;

    my $format = ($params{format}
		  ? $params{format}
		  : ($config{kalbum_long_caption}
		     ? $config{kalbum_long_caption}
		     : ($config{kalbum_short_caption}
			? $config{kalbum_short_caption}
			: '%Comment%')));
    my $user_cap = '';
    if ($params{caption})
    {
	$user_cap = $params{caption};
    }
    elsif (exists $pagestate{$image}{kalbum}{caption}
	and defined $pagestate{$image}{kalbum}{caption})
    {
	$user_cap = $pagestate{$image}{kalbum}{caption};
    }
    elsif (exists $pagestate{$image}{meta}{description}
	and defined $pagestate{$image}{meta}{description})
    {
	$user_cap = $pagestate{$image}{meta}{description};
    }
    my $out = '';
    my $items = 0;
    my $srcfile = srcfile($image, 1);
    if (defined $srcfile
	and -e $srcfile
	and $format)
    {
	my $info = Image::ExifTool::ImageInfo($srcfile);
	# add the basename
	my ($basename, $path, $suffix) = fileparse($srcfile, qr/\.[^.]*/);
	$basename =~ s/_/ /g;
	$info->{FileBase} = $basename;

	# only add the meta data if it's there
	my $fieldspec = $format;
	while ($fieldspec =~ /%([\w\s]+)%/g)
	{
	    my $field = $1;
	    if ($field eq 'caption' and $user_cap)
	    {
		my $fieldval = $user_cap;
		$fieldspec =~ s/%${field}%/$fieldval/g;
		$items++;
	    }
	    elsif ($field eq 'title')
	    {
		my $fieldval = pagetitle(IkiWiki::basename($image));
		$fieldval =~ s/\.\w+$//; # remove extension
		$fieldval =~ s/ (
			      (^\w)    #at the beginning of the line
			      |      # or
			      (\s\w)   #preceded by whitespace
			     )
		/\U$1/xg;
		$fieldspec =~ s/%${field}%/$fieldval/g;
		$items++;
	    }
	    elsif (exists $info->{$field}
		and defined $info->{$field}
		and $info->{$field})
	    {
		my $fieldval = $info->{$field};
		# make the fieldval HTML-safe
		$fieldval =~ s/&/&amp;/g;
		$fieldval =~ s/</&lt;/g;
		$fieldval =~ s/>/&gt;/g;
		$fieldspec =~ s/%${field}%/$fieldval/g;
		$items++;
	    }
	    else
	    {
		$fieldspec =~ s/%${field}%//g;
	    }
	}
	if ($items)
	{
	    $out = $fieldspec;
	}
    }
    return $out;
} # get_caption

sub include_styles ($;$) {
    my $page=shift;
    my $absolute=shift;
	
    my $size = $pagestate{$page}{kalbum}{size};
    $size =~ /(\d+)x(\d+)/;
    my $thumb_width = $1;
    my $thumb_height = $2;
    my $item_width = $thumb_width + 50;
    my $item_height = $thumb_height + 70;
    my $max_thumb_height = $thumb_height + 10;
    my $out = '';

    $out =<<EOT;
<style type="text/css">
/* album pages */
.item {
    float: left;
    vertical-align: middle;
    text-align: center;
    margin: 10px;
    width: ${item_width}px;
    height: ${item_height}px;
    font-size: small;
}
.item .caption {
    width: ${item_width}px;
    height: 2.4em;
    overflow: hidden;
}
.thumb {
    overflow: hidden;
    max-height: ${max_thumb_height}px;
}
</style>
EOT
    return $out;
} # include_styles

sub is_page ($) {
    my $page = shift;

    my $source=exists $IkiWiki::pagesources{$page} ?
	$IkiWiki::pagesources{$page} :
	$IkiWiki::delpagesources{$page};
    my $type=defined $source ? IkiWiki::pagetype($source) : undef;
    return (defined $type);
} # is_page

1
