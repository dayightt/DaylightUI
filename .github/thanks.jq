# Turns `gh pr list --json number,title,url,author` into a "Thanks to" section
# for the release notes. Leaves out the owner and bots; empty when no one else
# had a pull request merged.
[ .[] | select(.author.login != $owner and ((.author.is_bot // false) | not)) ]
| sort_by(.number)
| if length == 0 then empty else
    "\n## Thanks to\n\n"
    + (map("- \(.title | gsub("[\\[\\]\\n`]"; "")) by [\(.author.login)](https://github.com/\(.author.login)) ([#\(.number)](\(.url)))")
       | join("\n"))
  end
