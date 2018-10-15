#!/bin/bash

branch_prefix='rules/'
script_dir=$(dirname "$0")
page_names=()
dir_name=../../..
base_dir="$script_dir/$dir_name"
force=

function usage {
	echo "usage: $0 ((-p|--pagename) page_name)+ (-d|--dirname) dir_name [-f|--force]"
	echo "usage: $0 (-h|--help)"
}

while [ "$1" != "" ]; do
    case $1 in
        -p | --pagename )	shift
				page_names+=("$1")
                                ;;
        -d | --dirname )	shift
				base_dir="$1"
                                ;;
	-f | --force )		force=1
				;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

if [ ${#page_names[@]} -eq 0 ]; then
	echo "Missing page_name attribute" >&2
	usage
	exit
fi
if [ -z "$dir_name" ]; then
	echo "Missing dir_name attribute" >&2
	usage
	exit
fi
base_url="http://j2s-pendragon.wikia.com/wiki"
wiki_sub_dir="src/main/wiki"
img_sub_dir="src/main/img"
work_subdir="target/work"

tab=$'\t'

# Import images list

work_dir="$base_dir/$work_subdir"
mkdir -p "$work_dir"
images_file_html="$work_dir/images.html"
if [ "$force" -o  \! -f "$images_file_html" ]; then
	echo "Loading images list..."
	curl "$base_url/Special:Images" -o - > "$images_file_html"
fi
images_file_xml="$work_dir/images.xml"
if [ "$force" -o  \! -f "$images_file_xml" ]; then
	echo "Converting images list to XML..."
	tidy -quiet -numeric -asxml -wrap 0 -o "$images_file_xml" "$images_file_html"
fi
images_file_data="$work_dir/images.data"
echo "Extracting data from images list..."
if [ "$force" -o  \! -f "$images_file_data" ]; then
	xpathmatch='//_:div[@class="wikia-gallery-item"]'
	xpathvalue='concat(descendant::_:a[@class="wikia-gallery-item-posted"], "'"$tab"'", descendant::_:i, "'"$tab"'", descendant::_:img/@data-image-key)'
	xml sel -t -m "$xpathmatch" -v "$xpathvalue" -n "$images_file_xml" | perl -CIO -pe '
		BEGIN { use Time::Piece; };
		my($referrer, $date, $image) = split "\t";
		$t = Time::Piece->strptime($date, "%B %d, %Y");
		$_ = join("\t", ($referrer, $t->strftime("%Y-%m-%d"), $image))
		' > "$images_file_data"
	echo Found $(wc -l < "$images_file_data") images
fi

for page_name in "${page_names[@]}"; do

echo "* Processing page $page_name"
mkdir -p "$base_dir/$img_sub_dir"

git co "$branch_prefix"wikia/images
grep -p "^$page_name"'\t' "$images_file_data" | \
sort -k2 | \
while read image_record; do
	image=$(echo "$image_record" | awk 'BEGIN {FS="\t"} { print $3 }' )
	echo "  - Processing $image for $page_name..."
	history_image_html="$work_dir/File:$image.html"
	if [ "$force" -o  \! -f "$history_image_html" ]; then
		echo "Loading history for $image..."
		curl "$base_url/File:$image" -o - > "$history_image_html"
	fi
	history_image_xml="$work_dir/File:$image.xml"
	if [ "$force" -o  \! -f "$history_image_xml" ]; then
		echo "Converting history for $image to XML..."
		tidy -quiet -numeric -asxml -wrap 0 -o "$history_image_xml" "$history_image_html"
	fi
	history_image_data="$work_dir/File:$image.data"
	if [ "$force" -o  \! -f "$history_image_data" ]; then
		echo "Extracting data from history for $image..."
		xpathmatch='//_:td[text()="current"]/following-sibling::_:td[position()=1]'
		xpathvalue='.'
		xml sel -t -m "$xpathmatch" -v "$xpathvalue" -n "$history_image_xml" | perl -CIO -pe '
		BEGIN { use Time::Piece; };
		chomp;
		$t = Time::Piece->strptime($_, "%H:%M, %B %d, %Y"); # TODO: UTC?
		$_ = $t->strftime("%Y-%m-%dT%H:%MZ")
		' > "$history_image_data"
	fi
	image_file="$base_dir/$img_sub_dir/$image"
	if [ "$force" -o  \! -f "$image_file" -o \! -s "$image_file" ]; then
		xpathmatch='//_:div[@class="fullImageLink"]/_:a'
		xpathvalue='@href'
		image_url=$(xml sel -t -m "$xpathmatch" -v "$xpathvalue" -n "$history_image_xml")
		if [ "$image_url" ]; then
			echo "$image_url"
			curl "$image_url" -o "$image_file"
		else
			echo "URL not found for $image, skipping."
		fi
	fi
	if [ -s "$image_file" ]; then
		git add "$image_file"
		#timestamp=$(cat "$history_image_data")
		timestamp=$(cat "$history_image_data")"Z"
		git commit --date="${timestamp}" -m "imported image: $image"
		git log -n 1
	else
		echo "$image missing, skipping."
	fi
done

done

git checkout "$branch_prefix"master
git merge --no-edit "$branch_prefix"wikia/images

