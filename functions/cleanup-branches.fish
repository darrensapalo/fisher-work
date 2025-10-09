# This removes branches from your local machine.
#
# Very handy when you'd like to clean up feature/bugfix branches on your local machine.
#
# Usage:
#   cleanup-branches           # Show all branches
#   cleanup-branches merged    # Show only merged branches
#   cleanup-branches unmerged  # Show only unmerged branches
#
# See article: https://devconnected.com/how-to-clean-up-git-branches/
function cleanup-branches
  set filter $argv[1]
  
  # Step 1: Get branches based on filter and format with details
  # Format: branch_name | last_commit_date
  set formatted_branches (
    if test "$filter" = "merged"
      git branch --merged
    else if test "$filter" = "unmerged"
      git branch --no-merged
    else
      git branch
    end | \
    grep -v '^\*' | \
    sed 's/^[[:space:]]*//' | \
    while read branch
      set commit_date (git log -1 --format=%ci $branch 2>/dev/null | cut -d' ' -f1)
      printf "%-50s  %s\n" "$branch" "$commit_date"
    end)
  
  # Step 2: Use fzf to select branch with formatted display
  # Step 3: Extract just the branch name (first column)
  # Step 4: Delete the selected branch
  set header_text "Branch                                              Date"
  if test "$filter" = "merged"
    set header_text "$header_text (merged only)"
  else if test "$filter" = "unmerged"
    set header_text "$header_text (unmerged only)"
  end
  
  set selected_branch (printf "%s\n" $formatted_branches | \
    fzf --header="$header_text" \
        --header-lines=0 \
        --preview='git log --oneline --graph --color=always {1} -10' \
        --preview-window=right:50% | \
    awk '{print $1}')
  
  if test -n "$selected_branch"
    git branch -D $selected_branch
  end
end
