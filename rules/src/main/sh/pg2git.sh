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
		BEGIN {
			$last_line_empty = 0;
		}
		if ($last_line_empty) {
			if (! m:^\*\*:) {
				print "\n";
			}
			$last_line_empty = 0;
		}
		if (m:^$:) {
			$last_line_empty = 1;
			$_ = "";
			next;
		}
		s:^'"'''"'(.*?)'"'''"'<br.*?/>$:$1\n:; # fix hardcoded document title
		s:^<h2.*?>(.*?)</h2>$:==$1==:; # fix hardcoded heading
		s:^=\s*([^=]*?)\s*=$:'"'''"'$1'"'''"':; # fix level 1 pseudo-header
		s:^=(.*)=$:$1:; # promote all headers
		s:^<div\s+style="page-break-after\:\s+always"></div>$:\n>> PAGEBREAK HERE <<\n:; # remember hardcoded page break
		s:\+:%%plus%%:g; # remember plus sign
		s:(?<!-)-(?!–):%%minus%%:g; # remember isolated minus sign
		s:~:%%tilde%%:g; # remember tilde sign
		s:<s>:%%s%:g; # remember strike-through
		s:</s>:%/s%%:g; # remember strike-through
		s:<u>:%%u%:g; # remember underline
		s:</u>:%/u%%:g; # remember underline
		s:\[\[#([^\]]+)\]\]:%%anchor%$1%/anchor%%:g; # remember anchor
		s/^(:[:\*]*)/\n%$1%%/; # remember indent
		s:<blockquote>:%%blockquote%:g; # remember blockquote
		s:</blockquote>:%blockquote%%:g; # remember blockquote
		s:(?<!'\'')'\''([^ '\'']+?)'\''(?!'\''):%%'\''%$1%'\''%%:g; # remember single quoted words
		s#[\|\!](:?(r)ow|(c)ol)span="(\d+)".*?\|#$&%%$2$3$4%%#g; # remember colspan/rowspan
		s:<br>:%%br%%:g; # remember line breaks
		s:&beta;:%%beta%%:g; # remember beta character
		s:\|thumb\]\]:$&%%thumb%%:g; # remember thumb images
	' "$wiki_page_path" | tee "$wiki_page_path".fix | \
	pandoc -f mediawiki -t asciidoc --toc | tee "$adoc_page_path".temp | \
		perl -pe 'BEGIN {
			use utf8;
			use Text::Unidecode;
			use Encode "decode";
			binmode STDIN, ":utf8";
			binmode STDOUT, ":utf8";
			$last_line_empty = 0;
			$list_level = 0;
			$in_em_block = 0;
			}
			if ($last_line_empty) {
				if (m/^%(:[:\*]*\*)%%/ && $list_level) {
					# dismiss empty line
				} elsif (m/^%(:[:\*]*)%%/ && (length($1)>=$list_level) && $list_level) {
					# dismiss empty line
				} else {
					print "\n"; # keep empty line
				  $list_level = 0;
				}
				$last_line_empty = 0;
			}
			if (m:^$:) {
				$last_line_empty = 1;
				$_ = "";
				next;
			}
			if ($. == 1) {
				s:%%plus%%:+:g; # fix plus sign
				$sub = "=" x (length($_)-1);
				s{$}{
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
:em: pass:[<em>]
:_em: pass:[</em>]
:beta: pass:[&beta;]
:plus: pass:[&#43;]
:minus: pass:[&#45;]
:tilde: pass:[&#126;]
};
			}
			s/>> PAGEBREAK HERE <</<<<\ntoc::[]\n<<</; # fix hardcoded page break
			s/^\[\[.*?\]\]$/unidecode(decode "UTF-8", $&)/e; # fix identifiers with accents
			s:%%plus%%:{plus}:g; # fix plus sign
			s:^%%minus%%:{minus}:g; # fix minus sign
			s:%%minus%%:-:g; # fix minus sign
			s:%%tilde%%:{tilde}:g; # fix tilde sign
			s:%%s%\s*:[line-through]#:g; # fix strike-through
			s:\s*%/s%%:#:g; # fix strike-through
			s:%%u%\s*:[underline]#:g; # fix underline
			s:\s*%/u%%:#:g; # fix underline
			s:%%anchor%(.*)%/anchor%%:<<_@{[lc($1)]},$1>>:g; # fix anchor
			s:%%'\''%([^ '\'']+?)%'\''%%:'\''$1'\'':g; # fix single quoted words
			s:\|%%c(\d+)%%:$1+|:g; # fix colspan
			s:\|%%r(\d+)%%:.$1+|:g; # fix rowspan
			s:%%br%%:{br}:g; # fix line breaks
			s:%%beta%%:{beta}:g; # fix beta character
			unless ($list_level) {
				s/^%(:+)%%/[none]\n@{["*" x length($1)]}/; # fix indent
				s/ %(:+)%%/\n[none]\n@{["*" x length($1)]}/g; # fix indent
			} else {
				s/^%(:+)%%/$1/; # fix indent
				s/ %(:+)%%/\n$1/g; # fix indent
			}
			s/^%(:[:\*]*\*)%%/@{["*" x length($1)]}/; # fix indent
			s/ %(:[:\*]*\*)%%/\n@{["x" x length($1)]}/g; # fix indent
			s:%%blockquote%:\n****\n:g; # fix blockquote
			s:%blockquote%%:\n****\n:g; # fix blockquote
			s/(image:.*?\[)(.*?),/\1"\2",/g; # fix images alt attribute
			s:\]%%thumb%%:,width=180]:g; # fix thumb images
			if (m/^([:*]+) /) {
				$list_level = length($1);
			}
			if ($in_em_block) {
				if (s:'\'\'':{_em}:) {
					$in_em_block = 0;
				}
			} elsif (s:'\'\'':{em}:) {
				# fix remaining double single quotes (italic in wiki)
				$in_em_block = 1;
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

