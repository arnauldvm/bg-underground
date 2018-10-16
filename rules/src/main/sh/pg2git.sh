#!/bin/sh

# Dependencies
for cmd in git xmlstarlet perl pandoc; do
    command -v "$cmd" >/dev/null 2>&1 || { echo >&2 "Could not find required command '$cmd', aborting."; exit 1; }
done
for mod in utf8 Text::Unidecode Encode; do
    perl -e "use $mod" >/dev/null 2>&1 || { echo >&2 "Could not find required perl module '$mod', aborting."; exit 1; }
done

infile="$1"
if [ \! -s "$infile" ]; then
	echo Missing infile argument, aborting.
	echo "Go to https://j2s-pendragon.wikia.com/wiki/Special:Export"
	echo "    and export the whole history of the page you want to convert"
	echo "    (only one page can be converted at a time)"
	exit 1
fi

branch_prefix='rules/'
script_dir=$(dirname "$0")
dir_name=../../..
base_dir="$script_dir/$dir_name"
wiki_sub_dir="src/main/wiki"
adoc_sub_dir="src/main/adoc"
work_subdir="target/work"
ns=http://www.mediawiki.org/xml/export-0.10/

page_title=$( xmlstarlet sel -T -N w=$ns \
	-t -m "//w:page" -v "w:title" \
	"$infile" )
revisions=($( xmlstarlet sel -T -N w=$ns \
		-t -m '//w:revision' -v 'w:id' --nl \
		"$infile" ))

echo Found ${#revisions[@]} revisions

mkdir -p "$base_dir/$wiki_sub_dir"
wiki_page_path="$base_dir/$wiki_sub_dir/${page_title}.wiki"
mkdir -p "$base_dir/$adoc_sub_dir"
adoc_page_path="$base_dir/$adoc_sub_dir/${page_title}.adoc"
work_dir="$base_dir/$work_subdir/$page_title"
mkdir -p "$work_dir"
git stash save "Saved before importing files"; git stash apply
git checkout "$branch_prefix"master
git reset --hard "$branch_prefix"import/code
git branch -D "$branch_prefix"wikia/pages
git branch -D "$branch_prefix"wikia/images
git branch -D "$branch_prefix"adoc
git gc
git branch "$branch_prefix"wikia/pages
git branch "$branch_prefix"wikia/images
git branch "$branch_prefix"adoc
for revision in ${revisions[@]}; do
	git checkout "$branch_prefix"wikia/pages
	xmlstarlet sel -T -N w=$ns -E utf-8 \
		-t -m "//w:revision[w:id='$revision']" -v 'w:text' \
		"$infile" > "$wiki_page_path"
	timestamp=$( xmlstarlet sel -T -N w=$ns \
		-t -m "//w:revision[w:id='$revision']" -v 'w:timestamp' \
		"$infile" )
	comment=$( xmlstarlet sel -T -N w=$ns \
		-t -m "//w:revision[w:id='$revision']" -v 'w:comment' \
		"$infile" |
		perl -pe 's#/\*\s+(.*)\s+\*?/#(\1):#g' )
	echo "$revision - $timestamp : $comment"
	git add "$wiki_page_path"
	git commit --date="$timestamp" -m "$comment"
	git log -n 1
	#cp "$wiki_page_path" "$work_dir"
	git checkout "$branch_prefix"adoc
	git merge --no-commit "$branch_prefix"wikia/pages
	perl -pe '
		s:^'"'''"'(.*?)'"'''"'<br.*?/>$:$1\n:; # fix hardcoded document title
		s:^<h2.*?>(.*?)</h2>$:==$1==:; # fix hardcoded heading
		s:^=\s*([^=]*?)\s*=$:'"'''"'$1'"'''"':; # fix level 1 pseudo-header
		s:^=(.*)=$:$1:; # promote all headers
		s:^<div\s+style="page-break-after\:\s+always"></div>$:\n>> PAGEBREAK HERE <<\n:; # remember hardcoded page break
		s:<s>(.*?)</s>:%%s%$1%/s%%:g; # remember strike-through
		s:<u>(.*?)</u>:%%u%$1%/u%%:g; # remember underline
		s:(?<!'\'')'\''([^ '\'']+?)'\''(?!'\''):%%'\''%$1%'\''%%:g; # remember single quoted words
		s#[\|\!](:?(r)ow|(c)ol)span="(\d+)".*?\|#$&%%$2$3$4%%#g; # remember colspan/rowspan
		s:<br>:%%br%%:g; # remember line breaks
		s:&beta;:%%beta%%:g; # remember beta character
		s:\|thumb\]\]:$&%%thumb%%:g; # remember thumb images
	' "$wiki_page_path" | \
	pandoc -f mediawiki -t asciidoc --toc | \
		perl -pe 'BEGIN {
			use utf8;
			use Text::Unidecode;
			use Encode "decode";
			$in_side_block = 0;
			}
			$sub = "=" x (length($_)-1);
			($. == 1) and s{$}{
$sub
:author: Arnauld Van Muysewinkel <arnauldvm\@gmail.com>'"
:revnumber: W$revision
:revdate: ${timestamp:0:10}
//:revremark: $comment"'
:doctype: article
:lang: fr
:encoding: utf8
:toc:
:toc-placement: manual
:toclevels: 4
:toc-title: Contenu
//:numbered:
:imagesdir: ../img
//:data-uri: // This corrupts some images because of a bug in base64 encoding, see https://github.com/asciidoc/asciidoc/issues/98 and https://groups.google.com/d/topic/asciidoc/pC22vFTCxTc/discussion
:br: pass:[<br>]
:beta: pass:[&beta;]
};
			s/>> PAGEBREAK HERE <</<<<\ntoc::[]\n<<</; # fix hardcoded page break
			s/^\[\[.*?\]\]$/unidecode(decode "UTF-8", $&)/e; # fix identifiers with accents
			s:%%s%:[line-through]#:g; # fix strike-through
			s:%/s%%:#:g; # fix strike-through
			s:%%u%:[underline]#:g; # fix underline
			s:%/u%%:#:g; # fix underline
			s:%%'\''%([^ '\'']+?)%'\''%%:'\''$1'\'':g; # fix single quoted words
			s:\|%%c(\d+)%%:$1+|:g; # fix colspan
			s:\|%%r(\d+)%%:.$1+|:g; # fix rowspan
			s:%%br%%:{br}:g; # fix line breaks
			s:%%beta%%:{beta}:g; # fix beta character
			s/(image:.*?\[)(.*?),/\1"\2",/g; # fix images alt attribute
			s:\]%%thumb%%:,width=180]:g; # fix thumb images
			if (s/^::$/****/) {
				$in_side_block = 1;
			} elsif ($in_side_block) {
				if (s/^$/****\n/) {
					$in_side_block = 0;
				} else {
					s/^  //;
				}
			}
		' > "$adoc_page_path"
	git add "$adoc_page_path"
	git commit --date="$timestamp" -m "convert: $comment"
	git log -n 1
done
git checkout "$branch_prefix"master
git merge --no-edit "$branch_prefix"adoc

src/main/sh/img2git.sh -p "${page_title}"

asciidoc "$adoc_page_path"

