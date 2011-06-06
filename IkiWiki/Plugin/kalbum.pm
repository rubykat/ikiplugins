#!/usr/bin/perl
package IkiWiki::Plugin::kalbum;

use warnings;
use strict;
use IkiWiki 3.00;
use File::Basename;

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
					       all_values=>\&kalbum_get_values);
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
    my $size = ($params{size} ? $params{size} : "100x100");

    # process captions and thumbnails
    if ($params{image})
    {
	if ($params{caption})
	{
	    if ($scanning)
	    {
		$pagestate{$params{image}}{kalbum}{caption} = $params{caption};
	    }
	}
	if ($params{thumbnail})
	{
	    make_thumbnail(%params,
			   item=>$params{image},
			   size=>$size,
			   scanning=>$scanning);
	}
	return '';
    }

    my $pagespec = ($params{pages}
		    ? $params{pages}
		    : "${page}/* and !${page}/*/*"
		   );
    if ($scanning)
    {
	$size =~ /(\d+)x(\d+)/;
	my $thumb_width = $1;
	my $thumb_height = $2;
	$pagestate{$page}{kalbum}{thumb_width} = $thumb_width;
	$pagestate{$page}{kalbum}{thumb_height} = $thumb_height;
    }

    my $deptype=deptype('presence');
    my @items =
	pagespec_match_list($page, $pagespec,
			    location=>$page,
			    deptype => $deptype,
			    sort=>$params{sort},
			   );
    foreach my $item (@items)
    {
	make_thumbnail(%params,
		       size=>$size,
		       scanning=>$scanning,
		       item=>$item);
    }

    if (!$scanning)
    {
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
	    my $last = ($i == ($stop - 1));
	    make_image_page(%params,
			    image=>$item,
			    album=>$page,
			    prev_item=>$prev_item,
			    prev_page_url=>kalbum_get_value('img_page_url', $prev_item),
			    prev_thumb_url=>kalbum_get_value('thumb_url', $prev_item),
			    next_item=>$next_item,
			    next_page_url=>kalbum_get_value('img_page_url', $next_item),
			    next_thumb_url=>kalbum_get_value('thumb_url', $next_item),
			    first=>$first,
			    last=>$last,
			   );
	}

	my $out = '';
	if (@items)
	{
	    my $basename = IkiWiki::basename($page);
	    $out .= IkiWiki::Plugin::report::preprocess(%params,
							template=>($params{album_template}
								   ? $params{album_template}
								   : "kalbum"),
							report_id=>($params{report_id}
								    ? $params{report_id}
								    : $basename),
							albumdesc=>$params{albumdesc},
							pages=>$pagespec,
						       );
	}
	return $out;
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

	# make the content
	my $pout = '';
	eval {
	    $pout = IkiWiki::Plugin::ftemplate::preprocess(%page_params,
							   destpage=>'',
							   id=>($page_params{image_template}
								? $page_params{image_template}
								: "kalbum_image"),
							   image=>$page,
							   image_basename=>$img_basename,
							   caption=>$caption,
							   is_image=>0,
							   is_page=>1,
							   page_content=>$content,
							  );
	};
	if (!$pout)
	{
	    $pout=<<EOT;
ftemplate failed for $page
image_basename=$img_basename
prev_item=$page_params{prev_item}
next_item=$page_params{next_item}
EOT
	}
	else
	{
	}
	$content = $pout;
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
    if (!exists $pagestate{$page}{kalbum}{thumb_width}
	or !defined $pagestate{$page}{kalbum}{thumb_width})
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

    # figure out new pagename
    my $new_page = $image;
    $new_page =~ s{\.\w+$}{};
    my $target = targetpage('', $config{htmlext}, $new_page);

    my $is_image = ($image =~ $config{kalbum_image_regexp});
    my $caption = get_caption(%params);
    my $img_basename = IkiWiki::basename($image);

    # make the content
    my $pout = '';
    eval {
	$pout = IkiWiki::Plugin::ftemplate::preprocess(%params,
		       destpage=>$new_page,
		       id=>($params{image_template}
			    ? $params{image_template}
			    : "kalbum_image"),
		       image=>$image,
		       image_basename=>$img_basename,
		       caption=>$caption,
		       is_image=>$is_image,
		      );
    };
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

sub alter_existing_page {
    my %params=@_;
    my $this_page = $params{image};
 
} # alter_existing_page

sub make_thumbnail {
    my %params=@_;
    my $item = $params{item};
    my $size = $params{size};

    # if we are not scanning, and we don't have a thumb_src
    # then we aren't going to be making a thumbnail - bye!
    if (!$params{scanning}
	and !exists $pagestate{$item}{kalbum}{thumb_src})
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

    # if we are scanning, figure out the data for the thumbnail and remember it
    if ($params{scanning})
    {
	add_link($params{page}, $item);
	add_depends($params{page}, $item);

	$pagestate{$item}{kalbum}{image_basename} = $basename;

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
	# the image itself it the item is an image,
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

	$thumb_url=urlto($thumb_link, 'index', 1);
	$pagestate{$item}{kalbum}{thumb_url} = $thumb_url;

	# if we are scanning, return before we write file
	return;
    }
    
    # We are NOT scanning. Make the thumbnail.
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
    foreach my $fn (qw(img_page_url short_caption caption is_image))
    {
	$values{$fn} = kalbum_get_value($fn, $params{page});
    }
    return \%values;
} # kalbum_get_values

sub kalbum_get_value ($$) {
    my $field_name = shift;
    my $page = shift;

    if ($field_name eq 'img_page_url')
    {
	my $url = IkiWiki::urlto($page, 'index', 1);
	if ($url =~ /(.*)\.\w+$/)
	{
	    my $val = "${1}.$config{htmlext}";
	    return $val;
	}
	else
	{
	    return $url;
	}
    }
    elsif ($field_name eq 'short_caption')
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
	$user_cap .= $params{caption};
	$user_cap .= ' ';
    }
    if (exists $pagestate{$image}{kalbum}{caption}
	and defined $pagestate{$image}{kalbum}{caption})
    {
	$user_cap .= $pagestate{$image}{kalbum}{caption};
	$user_cap .= ' ';
    }
    if (exists $pagestate{$image}{meta}{description}
	and defined $pagestate{$image}{meta}{description})
    {
	$user_cap .= $pagestate{$image}{meta}{description};
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
		# make the fieldval HTML-safe
		$fieldval =~ s/&/&amp;/g;
		$fieldval =~ s/</&lt;/g;
		$fieldval =~ s/>/&gt;/g;
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
	
    my $thumb_width = $pagestate{$page}{kalbum}{thumb_width};
    my $thumb_height = $pagestate{$page}{kalbum}{thumb_height};
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
.images:after, .dirs:after {
    content: ".";
    display: block;
    height: 0;
    clear: both;
    visibility: hidden;
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
