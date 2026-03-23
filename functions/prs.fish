function prs --description "PR splitting and management tool"
    set -l cmd $argv[1]
    set -l args $argv[2..-1]
    
    switch $cmd
        case commit
            __prs_commit $args
        case init
            __prs_init $args
        case split-commit
            __prs_split_commit $args
        case list
            __prs_list $args
        case review
            __prs_review $args
        case validate
            __prs_validate $args
        case create
            __prs_create $args
        case push
            __prs_push $args
        case status
            __prs_status $args
        case rebase-chain
            __prs_rebase_chain $args
        case undo
            __prs_undo $args
        case reset
            __prs_reset $args
        case finish
            __prs_finish $args
        case ""
            __prs_help
        case '*'
            echo "Unknown command: $cmd"
            __prs_help
            return 1
    end
end

function __prs_help
    echo "prs - PR splitting and management tool"
    echo ""
    echo "Commands:"
    echo "  prs commit [-m <message>] [-c <category>] [--no-interactive]"
    echo "      Commit with category"
    echo ""
    echo "  prs init [--create|--use-defaults]"
    echo "      Start splitting session"
    echo ""
    echo "  prs split-commit <hash>"
    echo "      Split mixed commit"
    echo ""
    echo "  prs list [--interactive]"
    echo "      Show categorized commits (non-interactive by default)"
    echo ""
    echo "  prs review <category> [options]"
    echo "      --summary              Show summary without full diffs"
    echo "      --files                Show only files changed per commit"
    echo "      --no-interactive       Non-interactive mode"
    echo ""
    echo "  prs validate [--verbose]"
    echo "      Check for categorization issues and mixed commits"
    echo ""
    echo "  prs create <category> [options]"
    echo "      --base <branch>        Base branch (default: main)"
    echo "      --ticket <number>      Ticket number"
    echo "      --description <desc>   PR description"
    echo "      --all                  Select all commits"
    echo "      --commits <hash,hash>  Specific commits to include"
    echo "      --local-only           Create branch locally, don't push/create PR"
    echo "      -y, --yes              Skip confirmation"
    echo ""
    echo "  prs push [branch-name]"
    echo "      Push local branch and create PR (after testing with --local-only)"
    echo ""
    echo "  prs status"
    echo "      View session progress"
    echo ""
    echo "  prs rebase-chain [-y|--yes]"
    echo "      Rebase dependent PRs after parent merges"
    echo ""
    echo "  prs undo [-y|--yes]"
    echo "      Delete last created PR"
    echo ""
    echo "  prs reset [-y|--yes]"
    echo "      Delete all PRs, start over"
    echo ""
    echo "  prs finish"
    echo "      Clean up session"
end

function __prs_config_dir
    echo "$HOME/.config/prs"
end

function __prs_config_file
    echo (__prs_config_dir)/config
end

function __prs_session_dir
    git rev-parse --git-dir 2>/dev/null | read -l gitdir
    if test -z "$gitdir"
        return 1
    end
    echo "$gitdir/prs-session"
end

function __prs_ensure_config_dir
    set -l config_dir (__prs_config_dir)
    if not test -d $config_dir
        mkdir -p $config_dir
    end
end

function __prs_get_repo_path
    git rev-parse --show-toplevel 2>/dev/null
end

function __prs_load_config
    set -l config_file (__prs_config_file)
    set -l repo_path (__prs_get_repo_path)
    
    if not test -f $config_file
        return 1
    end
    
    if test -z "$repo_path"
        return 1
    end
    
    set -g __prs_config_patterns
    set -g __prs_config_prefix
    set -g __prs_config_show_commands true
    set -g __prs_config_detect_mixed true
    set -g __prs_config_editor $EDITOR
    
    set -l in_repo_section 0
    set -l section_header "[repo:$repo_path]"
    
    while read -l line
        set line (string trim $line)
        
        if test -z "$line"; or string match -q "#*" $line
            continue
        end
        
        if string match -q "\[defaults\]" $line
            set in_repo_section 0
            continue
        end
        
        if test "$line" = "$section_header"
            set in_repo_section 1
            continue
        end
        
        if string match -q "\[repo:*" $line
            if not test "$line" = "$section_header"
                set in_repo_section 0
            end
            continue
        end
        
        if string match -q "*=*" $line
            set -l key (string split -m 1 "=" $line)[1]
            set -l value (string split -m 1 "=" $line)[2]
            set key (string trim $key)
            set value (string trim $value)
            
            if test $in_repo_section -eq 1
                if string match -q "patterns.*" $key
                    set -l category (string split "." $key)[2]
                    set -a __prs_config_patterns "$category:$value"
                else if test "$key" = "naming.prefix"
                    set -g __prs_config_prefix $value
                end
            else
                if test "$key" = "show_commands"
                    set -g __prs_config_show_commands $value
                else if test "$key" = "detect_mixed"
                    set -g __prs_config_detect_mixed $value
                else if test "$key" = "editor"
                    set -g __prs_config_editor $value
                end
            end
        end
    end < $config_file
    
    return 0
end

function __prs_create_config_interactive
    set -l repo_path (__prs_get_repo_path)
    if test -z "$repo_path"
        echo "Error: Not in a git repository"
        return 1
    end
    
    echo ""
    echo "Creating config for: $repo_path"
    echo ""
    
    set -l patterns
    
    while true
        read -P "Category name (or 'done'): " category
        if test "$category" = "done"
            break
        end
        
        if test -z "$category"
            continue
        end
        
        read -P "File patterns (glob): " pattern
        if test -z "$pattern"
            continue
        end
        
        set -a patterns "$category:$pattern"
    end
    
    read -P "PR prefix (e.g., darren/PROJ-): " prefix
    
    __prs_ensure_config_dir
    set -l config_file (__prs_config_file)
    
    if test -f $config_file
        set -l has_section (grep -c "^\[repo:$repo_path\]" $config_file 2>/dev/null)
        if test $has_section -eq 0
            echo "" >> $config_file
            echo "[repo:$repo_path]" >> $config_file
        end
    else
        echo "[defaults]" > $config_file
        echo "show_commands = true" >> $config_file
        echo "detect_mixed = true" >> $config_file
        echo "editor = vim" >> $config_file
        echo "" >> $config_file
        echo "[repo:$repo_path]" >> $config_file
    end
    
    set -l temp_file (mktemp)
    set -l in_section 0
    set -l section_written 0
    
    if test -f $config_file
        while read -l line
            if string match -q "\[repo:$repo_path\]" $line
                set in_section 1
                set section_written 1
                echo $line >> $temp_file
                
                for p in $patterns
                    set -l cat (string split ":" $p)[1]
                    set -l pat (string split ":" $p)[2]
                    echo "patterns.$cat = $pat" >> $temp_file
                end
                
                if test -n "$prefix"
                    echo "naming.prefix = $prefix" >> $temp_file
                end
                continue
            end
            
            if test $in_section -eq 1
                if string match -q "\[*" $line
                    set in_section 0
                    echo $line >> $temp_file
                end
                continue
            end
            
            echo $line >> $temp_file
        end < $config_file
        
        mv $temp_file $config_file
    end
    
    echo ""
    echo "▶ Saving config to $config_file"
    echo ""
    echo "Config saved! Run 'prs init' again to start."
end

function __prs_init
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository"
        return 1
    end
    
    set -l repo_path (__prs_get_repo_path)
    echo ""
    echo "▶ pwd"
    echo $repo_path
    echo ""
    
    set -l create_config 0
    set -l use_defaults 0
    
    for arg in $argv
        switch $arg
            case --create
                set create_config 1
            case --use-defaults
                set use_defaults 1
        end
    end
    
    if not __prs_load_config
        if test $create_config -eq 1
            __prs_create_config_interactive
            return
        else if test $use_defaults -eq 1
            set -g __prs_config_patterns \
                "schema:migrations/**,**/schema.*,**/models/schema.py,**/enums.*" \
                "tests:**/*test.*,**/*spec.*,**/tests/**" \
                "api:**/routes/**,**/controllers/**,**/api/**" \
                "data:**/repositories/**,**/queries/**,**/db/**"
            set -g __prs_config_prefix "feature/"
        else
            echo "No config found for this repository."
            echo ""
            echo "Options:"
            echo "  [c] Create config for this repo"
            echo "  [u] Use default patterns"
            echo "  [q] Quit"
            echo ""
            
            read -P "Choice: " choice
            
            switch $choice
                case c
                    __prs_create_config_interactive
                    return
                case u
                    set -g __prs_config_patterns \
                        "schema:migrations/**,**/schema.*,**/models/schema.py,**/enums.*" \
                        "tests:**/*test.*,**/*spec.*,**/tests/**" \
                        "api:**/routes/**,**/controllers/**,**/api/**" \
                        "data:**/repositories/**,**/queries/**,**/db/**"
                    set -g __prs_config_prefix "feature/"
                case '*'
                    echo "Cancelled"
                    return 1
            end
        end
    else
        set -l pattern_count (count $__prs_config_patterns)
        echo "Loading config for: $repo_path"
        echo "Found $pattern_count pattern categories"
        if test -n "$__prs_config_prefix"
            echo "Naming prefix: $__prs_config_prefix"
        end
        echo ""
    end
    
    set -l session_dir (__prs_session_dir)
    if test -d $session_dir
        echo "Session already exists. Continue? (Y/n)"
        read -l response
        if test "$response" = "n"
            return 1
        end
    else
        mkdir -p $session_dir
        echo "commits" > $session_dir/commits.txt
        echo "branches" > $session_dir/branches.txt
    end
    
    echo "Initializing split session..."
    echo ""
    __prs_categorize_commits
end

function __prs_categorize_commits
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    set -l main_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if test -z "$main_branch"
        set main_branch "main"
    end
    
    set -l commits (git log --oneline origin/$main_branch..HEAD 2>/dev/null)
    if test -z "$commits"
        echo "No commits to categorize."
        return 0
    end
    
    echo -n > $session_dir/commits.txt
    
    printf '%s\n' $commits | while read -l hash message
        set -l category "uncategorized"
        set -l files (git diff-tree --no-commit-id --name-only -r $hash)
        
        for pattern_entry in $__prs_config_patterns
            set -l cat (string split ":" $pattern_entry)[1]
            set -l patterns_str (string split ":" $pattern_entry)[2]
            set -l patterns (string split "," $patterns_str)
            
            for file in $files
                for pattern in $patterns
                    set pattern (string trim $pattern)
                    if __prs_glob_match $file $pattern
                        set category $cat
                        break
                    end
                end
                if test "$category" != "uncategorized"
                    break
                end
            end
            if test "$category" != "uncategorized"
                break
            end
        end
        
        echo "$hash $category $message" >> $session_dir/commits.txt
    end
    
    if test "$__prs_config_detect_mixed" = "true"
        __prs_detect_mixed_commits
    end
end

function __prs_glob_match
    set -l file $argv[1]
    set -l pattern $argv[2]
    
    if string match -q "**/*" $pattern
        set pattern (string sub -s 4 $pattern)
        if string match -q "*$pattern" $file
            return 0
        end
    else if string match -q "*/**" $pattern
        set pattern (string sub -e -3 $pattern)
        if string match -q "$pattern/*" $file
            return 0
        end
    else if string match -q "*" $pattern
        if string match -q $pattern $file
            return 0
        end
    end
    
    return 1
end

function __prs_detect_mixed_commits
    set -l session_dir (__prs_session_dir)
    
    while read -l line
        set -l hash (echo $line | awk '{print $1}')
        set -l category (echo $line | awk '{print $2}')
        
        set -l files (git diff-tree --no-commit-id --name-only -r $hash)
        set -l categories
        
        for file in $files
            for pattern_entry in $__prs_config_patterns
                set -l cat (string split ":" $pattern_entry)[1]
                set -l patterns_str (string split ":" $pattern_entry)[2]
                set -l patterns (string split "," $patterns_str)
                
                for pattern in $patterns
                    set pattern (string trim $pattern)
                    if __prs_glob_match $file $pattern
                        if not contains $cat $categories
                            set -a categories $cat
                        end
                        break
                    end
                end
            end
        end
        
        if test (count $categories) -gt 1
            echo "⚠️  Mixed commit detected: $hash"
            echo "    Categories: "(string join ", " $categories)
        end
    end < $session_dir/commits.txt
end

function __prs_commit
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository"
        return 1
    end
    
    __prs_load_config
    
    set -l staged_files (git diff --cached --name-only)
    if test -z "$staged_files"
        echo "No staged files to commit"
        return 1
    end
    
    set -l message ""
    set -l category ""
    set -l no_interactive 0
    
    set -l i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case -m --message
                set i (math $i + 1)
                set message $argv[$i]
            case -c --category
                set i (math $i + 1)
                set category $argv[$i]
            case --no-interactive
                set no_interactive 1
        end
        set i (math $i + 1)
    end
    
    if test -z "$category"
        set -l categories
        
        for file in $staged_files
            for pattern_entry in $__prs_config_patterns
                set -l cat (string split ":" $pattern_entry)[1]
                set -l patterns_str (string split ":" $pattern_entry)[2]
                set -l patterns (string split "," $patterns_str)
                
                for pattern in $patterns
                    set pattern (string trim $pattern)
                    if __prs_glob_match $file $pattern
                        if not contains $cat $categories
                            set -a categories $cat
                        end
                        break
                    end
                end
            end
        end
        
        if test (count $categories) -eq 1
            set category $categories[1]
            echo "Auto-detected category: $category"
        else if test (count $categories) -gt 1
            if test $no_interactive -eq 1
                echo "Error: Multiple categories detected: "(string join ", " $categories)
                echo "Pass -c/--category when using --no-interactive"
                return 1
            end
            echo "Multiple categories detected: "(string join ", " $categories)
            echo "Select category:"
            for i in (seq (count $categories))
                echo "  [$i] $categories[$i]"
            end
            read -P "Choice: " choice
            if test $choice -ge 1; and test $choice -le (count $categories)
                set category $categories[$choice]
            end
        else
            if test $no_interactive -eq 1
                echo "Error: No category detected"
                echo "Pass -c/--category when using --no-interactive"
                return 1
            end
            set category "uncategorized"
            echo "No category detected."
            read -P "Enter category: " category
        end
    end
    
    if test -z "$message"
        if test $no_interactive -eq 1
            echo "Error: Commit message is required with --no-interactive"
            return 1
        end
        read -P "Commit message: " message
    end
    
    set -l full_message "$category: $message"
    
    echo ""
    echo "Will run: git commit -m \"$full_message\""
    if test $no_interactive -eq 1
        git commit -m $full_message
        set -l commit_status $status
        if test $commit_status -ne 0
            return $commit_status
        end
        echo ""
        echo "✓ Committed with category: $category"
        return 0
    end
    read -P "Commit? (Y/n): " confirm
    
    if test "$confirm" != "n"
        git commit -m $full_message
        set -l commit_status $status
        if test $commit_status -ne 0
            return $commit_status
        end
        echo ""
        echo "✓ Committed with category: $category"
    end
end

function __prs_list
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    if not test -f $session_dir/commits.txt
        echo "No commits to list."
        return 0
    end
    
    set -l interactive 0
    for arg in $argv
        if test "$arg" = "--interactive"
            set interactive 1
        end
    end
    
    echo ""
    echo "Auto-categorized commits:"
    echo ""
    
    set -l categories
    while read -l line
        set -l category (echo $line | awk '{print $2}')
        if not contains $category $categories
            set -a categories $category
        end
    end < $session_dir/commits.txt
    
    set -l index 1
    for category in $categories
        set -l cat_commits (grep "^[a-f0-9]\\+ $category " $session_dir/commits.txt | tail -r)
        set -l commit_count (printf '%s\n' $cat_commits | wc -l | string trim)
        
        echo "$category ($commit_count commits)"
        
        printf '%s\n' $cat_commits | while read -l line
            set -l hash (echo $line | awk '{print $1}')
            set -l msg (echo $line | cut -d' ' -f3-)
            echo "  [$index] $hash $msg"
            set index (math $index + 1)
        end
        echo ""
    end
    
    if test $interactive -eq 0
        return 0
    end
    
    while true
        echo "Press 'e' to edit categories | Press 'q' to quit"
        read -n 1 -P "" choice
        
        switch $choice
            case e
                __prs_edit_categories
                __prs_list $argv
                return
            case q
                break
            case '*'
                continue
        end
    end
end

function __prs_review
    set -l category $argv[1]
    
    if test -z "$category"
        echo "Usage: prs review <category> [--summary|--files|--no-interactive]"
        return 1
    end
    
    set -l show_summary 0
    set -l show_files_only 0
    set -l no_interactive 0
    
    set -l i 2
    while test $i -le (count $argv)
        switch $argv[$i]
            case --summary
                set show_summary 1
                set no_interactive 1
            case --files
                set show_files_only 1
                set no_interactive 1
            case --no-interactive
                set no_interactive 1
        end
        set i (math $i + 1)
    end
    
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    if not test -f $session_dir/commits.txt
        echo "No commits to review."
        return 0
    end
    
    __prs_load_config
    
    set -l cat_commits (grep "^[a-f0-9]\\+ $category " $session_dir/commits.txt | tail -r)
    if test -z "$cat_commits"
        echo "No commits found for category: $category"
        return 1
    end
    
    if test $show_summary -eq 1
        set -l total_commits (printf '%s\n' $cat_commits | wc -l | string trim)
        echo "Category: $category"
        echo "Total commits: $total_commits"
        echo ""
        
        set -l all_files
        printf '%s\n' $cat_commits | while read -l line
            set -l hash (echo $line | awk '{print $1}')
            set -l files (git diff-tree --no-commit-id --name-only -r $hash)
            for file in $files
                if not contains $file $all_files
                    set -a all_files $file
                end
            end
        end
        
        echo "Unique files changed: "(count $all_files)
        echo ""
        
        set -l index 1
        printf '%s\n' $cat_commits | while read -l line
            set -l hash (echo $line | awk '{print $1}')
            set -l msg (echo $line | cut -d' ' -f3-)
            echo "[$index] $hash - $msg"
            set index (math $index + 1)
        end
        
        return 0
    end
    
    if test $show_files_only -eq 1
        echo "Category: $category"
        echo ""
        
        set -l index 1
        printf '%s\n' $cat_commits | while read -l line
            set -l hash (echo $line | awk '{print $1}')
            set -l msg (echo $line | cut -d' ' -f3-)
            echo "[$index] $hash - $msg"
            git diff-tree --no-commit-id --name-status -r $hash | sed 's/^/    /'
            echo ""
            set index (math $index + 1)
        end
        
        return 0
    end
    
    if test $no_interactive -eq 1
        echo "Category: $category"
        echo ""
        
        printf '%s\n' $cat_commits | while read -l line
            set -l hash (echo $line | awk '{print $1}')
            set -l msg (echo $line | cut -d' ' -f3-)
            
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Commit: $hash"
            echo "Message: $msg"
            echo ""
            echo "Files changed:"
            git diff-tree --no-commit-id --name-status -r $hash
            echo ""
            git show --color=always $hash
            echo ""
        end
        
        return 0
    end
    
    set -l commit_list
    printf '%s\n' $cat_commits | while read -l line
        set -l hash (echo $line | awk '{print $1}')
        set -a commit_list $hash
    end
    
    set -l total_commits (printf '%s\n' $cat_commits | wc -l | string trim)
    set -l current 1
    
    while test $current -le $total_commits
        set -l line (printf '%s\n' $cat_commits | sed -n "$current p")
        set -l hash (echo $line | awk '{print $1}')
        set -l msg (echo $line | cut -d' ' -f3-)
        
        clear
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Category: $category | Commit $current/$total_commits"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Commit: $hash"
        echo "Message: $msg"
        echo ""
        echo "Files changed:"
        git diff-tree --no-commit-id --name-status -r $hash
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        git show --color=always $hash
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Navigation: [j]forward | [k]back | [r]ecategorize | [q]uit"
        read -n 1 -P "Choice: " choice
        echo ""
        
        switch $choice
            case j
                if test $current -lt $total_commits
                    set current (math $current + 1)
                else
                    echo "Last commit in category"
                    sleep 1
                end
            case k
                if test $current -gt 1
                    set current (math $current - 1)
                else
                    echo "First commit in category"
                    sleep 1
                end
            case r
                echo ""
                read -P "New category: " new_category
                if test -n "$new_category"
                    set -l old_line (grep "^$hash " $session_dir/commits.txt)
                    set -l old_msg (echo $old_line | cut -d' ' -f3-)
                    
                    set -l temp_file (mktemp)
                    while read -l commit_line
                        set -l commit_hash (echo $commit_line | awk '{print $1}')
                        if test "$commit_hash" = "$hash"
                            echo "$hash $new_category $old_msg" >> $temp_file
                        else
                            echo $commit_line >> $temp_file
                        end
                    end < $session_dir/commits.txt
                    
                    mv $temp_file $session_dir/commits.txt
                    echo "Recategorized to: $new_category"
                    
                    set cat_commits (grep "^[a-f0-9]\\+ $category " $session_dir/commits.txt)
                    set total_commits (printf '%s\n' $cat_commits | wc -l | string trim)
                    
                    if test $total_commits -eq 0
                        echo "No more commits in category: $category"
                        sleep 2
                        return 0
                    end
                    
                    if test $current -gt $total_commits
                        set current $total_commits
                    end
                    
                    sleep 1
                end
            case q
                return 0
            case '*'
                continue
        end
    end
end

function __prs_validate
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    if not test -f $session_dir/commits.txt
        echo "No commits to validate."
        return 0
    end
    
    __prs_load_config
    
    set -l verbose 0
    for arg in $argv
        if test "$arg" = "--verbose" ; or test "$arg" = "-v"
            set verbose 1
        end
    end
    
    echo "Validating categorization..."
    echo ""
    
    set -l categories
    while read -l line
        set -l category (echo $line | awk '{print $2}')
        if not contains $category $categories
            set -a categories $category
        end
    end < $session_dir/commits.txt
    
    set -l has_issues 0
    
    for category in $categories
        set -l cat_commits (grep "^[a-f0-9]\\+ $category " $session_dir/commits.txt | tail -r)
        set -l commit_count (printf '%s\n' $cat_commits | wc -l | string trim)
        
        set -l all_files
        set -l file_patterns
        
        printf '%s\n' $cat_commits | while read -l line
            set -l hash (echo $line | awk '{print $1}')
            set -l files (git diff-tree --no-commit-id --name-only -r $hash)
            for file in $files
                if not contains $file $all_files
                    set -a all_files $file
                    
                    set -l path_parts (string split "/" $file)
                    if test (count $path_parts) -gt 0
                        set -l dir $path_parts[1]
                        if not contains $dir $file_patterns
                            set -a file_patterns $dir
                        end
                    end
                end
            end
        end
        
        set -l unique_file_count (count $all_files)
        set -l pattern_count (count $file_patterns)
        
        if test $verbose -eq 1
            echo "✓ $category: $commit_count commits, $unique_file_count files, $pattern_count directories"
        end
        
        if test "$category" = "uncategorized" ; and test $commit_count -gt 0
            set has_issues 1
            echo "⚠️  Warning: $commit_count commits in 'uncategorized'"
        end
        
        if test $pattern_count -gt 5
            set has_issues 1
            echo "⚠️  Warning: $category touches $pattern_count different directories (might be too broad)"
        end
    end
    
    echo ""
    echo "Checking for mixed commits..."
    
    set -l mixed_count 0
    while read -l line
        set -l hash (echo $line | awk '{print $1}')
        set -l category (echo $line | awk '{print $2}')
        
        set -l files (git diff-tree --no-commit-id --name-only -r $hash)
        set -l detected_categories
        
        for file in $files
            for pattern_entry in $__prs_config_patterns
                set -l cat (string split ":" $pattern_entry)[1]
                set -l patterns_str (string split ":" $pattern_entry)[2]
                set -l patterns (string split "," $patterns_str)
                
                for pattern in $patterns
                    set pattern (string trim $pattern)
                    if __prs_glob_match $file $pattern
                        if not contains $cat $detected_categories
                            set -a detected_categories $cat
                        end
                        break
                    end
                end
            end
        end
        
        if test (count $detected_categories) -gt 1
            set has_issues 1
            set mixed_count (math $mixed_count + 1)
            echo "⚠️  Mixed commit: $hash (categories: "(string join ", " $detected_categories)")"
        end
    end < $session_dir/commits.txt
    
    echo ""
    
    if test $has_issues -eq 0
        echo "✅ No issues found. All commits are well categorized."
        return 0
    else
        echo "❌ Found categorization issues."
        echo ""
        echo "Suggestions:"
        if test $mixed_count -gt 0
            echo "  - Use 'prs split-commit <hash>' for mixed commits"
        end
        echo "  - Use 'prs review <category>' to verify each category"
        echo "  - Use 'prs list' then press 'e' to recategorize commits"
        return 1
    end
end

function __prs_edit_categories
    set -l session_dir (__prs_session_dir)
    set -l temp_file (mktemp)
    
    echo "# Edit categories below. Save and quit to apply changes." > $temp_file
    echo "# Format: commit_hash category" >> $temp_file
    echo "" >> $temp_file
    
    while read -l line
        set -l hash (echo $line | awk '{print $1}')
        set -l category (echo $line | awk '{print $2}')
        echo "$hash $category" >> $temp_file
    end < $session_dir/commits.txt
    
    set -l editor $__prs_config_editor
    if test -z "$editor"
        set editor $EDITOR
    end
    if test -z "$editor"
        set editor vim
    end
    
    eval $editor $temp_file
    
    set -l changes 0
    set -l new_commits (mktemp)
    
    while read -l line
        if string match -q "#*" $line; or test -z "$line"
            continue
        end
        
        set -l hash (echo $line | awk '{print $1}')
        set -l new_category (echo $line | awk '{print $2}')
        
        set -l old_line (grep "^$hash " $session_dir/commits.txt)
        set -l old_category (echo $old_line | awk '{print $2}')
        set -l message (echo $old_line | cut -d' ' -f3-)
        
        if test "$new_category" != "$old_category"
            set changes (math $changes + 1)
        end
        
        echo "$hash $new_category $message" >> $new_commits
    end < $temp_file
    
    mv $new_commits $session_dir/commits.txt
    rm $temp_file
    
    echo ""
    echo "▶ Reloading categories..."
    echo "Categories updated! $changes commits recategorized."
    echo ""
end

function __prs_create
    set -l category $argv[1]
    set -l base_branch ""
    set -l ticket ""
    set -l description ""
    set -l select_all 0
    set -l skip_confirm 0
    set -l specific_commits ""
    set -l local_only 0
    
    set -l i 2
    while test $i -le (count $argv)
        switch $argv[$i]
            case --base
                set i (math $i + 1)
                set base_branch $argv[$i]
            case --ticket
                set i (math $i + 1)
                set ticket $argv[$i]
            case --description
                set i (math $i + 1)
                set description $argv[$i]
            case --all
                set select_all 1
            case --commits
                set i (math $i + 1)
                set specific_commits $argv[$i]
            case --local-only
                set local_only 1
            case -y --yes
                set skip_confirm 1
        end
        set i (math $i + 1)
    end
    
    if test -z "$category"
        echo "Usage: prs create <category> [options]"
        return 1
    end
    
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    __prs_load_config
    
    set -l main_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if test -z "$main_branch"
        set main_branch "main"
    end
    
    if test -z "$base_branch"
        set -l branches
        set -a branches $main_branch
        
        if test -f $session_dir/branches.txt
            while read -l line
                if not test -z "$line"
                    set -a branches $line
                end
            end < $session_dir/branches.txt
        end
        
        echo ""
        echo "Base branch?"
        for i in (seq (count $branches))
            if test $i -eq 1
                echo "> $branches[$i]"
            else
                echo "  $branches[$i]"
            end
        end
        
        read -P "Select (1-"(count $branches)"): " base_choice
        if test -z "$base_choice"
            set base_choice 1
        end
        
        set base_branch $branches[$base_choice]
    end
    
    set -l parent_commits
    if test "$base_branch" != "$main_branch"
        echo ""
        echo "▶ Analyzing $base_branch..."
        set parent_commits (git log --oneline $main_branch..$base_branch)
        set -l parent_count (echo $parent_commits | wc -l | string trim)
        echo "This PR contains $parent_count commits. They will be automatically included."
        echo ""
    end
    
    set -l available_commits
    if test -f $session_dir/commits.txt
        set available_commits (grep "^[a-f0-9]\\+ $category " $session_dir/commits.txt | tail -r)
    end
    
    if test -z "$available_commits"
        echo "No commits found for category: $category"
        return 1
    end
    
    set -l selected_commits
    
    if test -n "$specific_commits"
        for hash in (string split "," $specific_commits)
            set -a selected_commits (string trim $hash)
        end
    else if test $select_all -eq 1
        printf '%s\n' $available_commits | while read -l line
            set -l hash (echo $line | awk '{print $1}')
            set -a selected_commits $hash
        end
    else
        set -l temp_file (mktemp)
        set -l index 1
        
        if test -n "$parent_commits"
            echo "Select ADDITIONAL commits for '$category' PR:"
            printf '%s\n' $parent_commits | tail -r | while read -l hash msg
                echo "  [skip] $hash $msg (from parent)" >> $temp_file
            end
        else
            echo "Select commits for '$category' PR:"
        end
        
        printf '%s\n' $available_commits | while read -l line
            set -l hash (echo $line | awk '{print $1}')
            set -l msg (echo $line | cut -d' ' -f3-)
            echo "  [$index] $hash $msg" >> $temp_file
            set index (math $index + 1)
        end
        
        if command -v fzf >/dev/null
            set -l selected (cat $temp_file | fzf --multi --bind 'tab:toggle,start:select-all' --preview 'git show --color=always {2}' --preview-window=right:70%:wrap | awk '{print $2}')
            rm $temp_file
            
            if test -z "$selected"
                echo "No commits selected"
                return 1
            end
            
            set selected_commits $selected
        else
            cat $temp_file
            rm $temp_file
            echo ""
            read -P "Enter commit numbers (space-separated): " selections
            
            for sel in (string split " " $selections)
                set -l line (printf '%s\n' $available_commits | sed -n "$sel p")
                set -l hash (echo $line | awk '{print $1}')
                set -a selected_commits $hash
            end
        end
    end
    
    if test -z "$ticket"
        echo ""
        read -P "Ticket number ($__prs_config_prefix): " ticket
    end
    
    if test -z "$description"
        read -P "Description: " description
    end
    
    set -l branch_name "$__prs_config_prefix$ticket-$category"
    
    echo ""
    echo "Preview branch structure:"
    echo "  Base: $base_branch"
    echo "  Additional commits: "(count $selected_commits)
    echo ""
    echo "Will run: git checkout -b $branch_name $base_branch"
    for commit in $selected_commits
        echo "Will run: git cherry-pick $commit"
    end
    
    if test $local_only -eq 0
        echo "Will run: git push origin $branch_name"
        echo "Will run: gh pr create --base $base_branch --head $branch_name --title \"$ticket: $description\""
    end
    echo ""
    
    if test $skip_confirm -eq 0
        if test $local_only -eq 1
            read -P "Create local branch? (Y/n): " confirm
        else
            read -P "Create branch and PR? (Y/n): " confirm
        end
        if test "$confirm" = "n"
            return 1
        end
    end
    
    echo ""
    echo "▶ git checkout -b $branch_name $base_branch"
    git checkout -b $branch_name $base_branch
    
    if test "$base_branch" != "$main_branch"
        echo "Already includes commits from parent PR ✓"
    end
    
    for commit in $selected_commits
        echo "▶ git cherry-pick $commit"
        if not git cherry-pick $commit
            echo "Cherry-pick failed. Resolve conflicts and run 'git cherry-pick --continue'"
            return 1
        end
    end
    
    if test $local_only -eq 1
        echo ""
        echo "✓ Local branch created: $branch_name"
        echo ""
        echo "Next steps:"
        echo "  1. Test your changes locally"
        echo "  2. Run: git push origin $branch_name"
        echo "  3. Run: gh pr create --base $base_branch --head $branch_name --title \"$ticket: $description\""
        echo ""
        echo "Or use: prs push $branch_name"
        
        echo "$branch_name $base_branch local" >> $session_dir/branches.txt
    else
        echo "▶ git push origin $branch_name"
        git push origin $branch_name
        
        echo "▶ gh pr create --base $base_branch --head $branch_name --title \"$ticket: $description\""
        set -l pr_url (gh pr create --base $base_branch --head $branch_name --title "$ticket: $description" 2>&1 | grep -o 'https://github.com[^[:space:]]*')
        
        echo ""
        echo "PR created: $pr_url"
        
        if test "$base_branch" != "$main_branch"
            echo "Note: When parent PR merges, rebase this PR onto $main_branch"
        end
        
        echo "$branch_name $base_branch $pr_url" >> $session_dir/branches.txt
    end
end

function __prs_push
    set -l branch_name $argv[1]
    
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    if test -z "$branch_name"
        set branch_name (git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if test -z "$branch_name"
            echo "Error: Not on a git branch"
            return 1
        end
    end
    
    set -l branch_info (grep "^$branch_name " $session_dir/branches.txt)
    if test -z "$branch_info"
        echo "Error: Branch not found in prs session: $branch_name"
        echo "This command only works for branches created with 'prs create --local-only'"
        return 1
    end
    
    set -l base_branch (echo $branch_info | awk '{print $2}')
    set -l pr_state (echo $branch_info | awk '{print $3}')
    
    if test "$pr_state" != "local"
        echo "Error: Branch already has a PR"
        echo "Use 'prs status' to see existing PRs"
        return 1
    end
    
    __prs_load_config
    
    set -l ticket (echo $branch_name | sed "s|$__prs_config_prefix||" | cut -d'-' -f1)
    set -l category (echo $branch_name | sed "s|$__prs_config_prefix$ticket-||")
    
    echo ""
    read -P "PR title: " title
    if test -z "$title"
        set title "$ticket: $category updates"
    end
    
    echo ""
    echo "Will run: git push origin $branch_name"
    echo "Will run: gh pr create --base $base_branch --head $branch_name --title \"$title\""
    echo ""
    
    read -P "Push and create PR? (Y/n): " confirm
    if test "$confirm" = "n"
        return 1
    end
    
    echo ""
    echo "▶ git push origin $branch_name"
    git push origin $branch_name
    
    echo "▶ gh pr create --base $base_branch --head $branch_name --title \"$title\""
    set -l pr_url (gh pr create --base $base_branch --head $branch_name --title "$title" 2>&1 | grep -o 'https://github.com[^[:space:]]*')
    
    echo ""
    echo "✓ PR created: $pr_url"
    
    set -l temp_file (mktemp)
    while read -l line
        set -l curr_branch (echo $line | awk '{print $1}')
        if test "$curr_branch" = "$branch_name"
            echo "$branch_name $base_branch $pr_url" >> $temp_file
        else
            echo $line >> $temp_file
        end
    end < $session_dir/branches.txt
    
    mv $temp_file $session_dir/branches.txt
end

function __prs_split_commit
    set -l hash $argv[1]
    
    if test -z "$hash"
        echo "Usage: prs split-commit <hash>"
        return 1
    end
    
    echo "Splitting commit: $hash"
    echo ""
    
    set -l files (git diff-tree --no-commit-id --name-only -r $hash)
    echo "Files in commit:"
    for file in $files
        echo "  $file"
    end
    echo ""
    
    git reset --soft $hash^
    git reset HEAD
    
    echo "Commit has been reset. Stage and commit files separately."
    echo "Use 'prs commit' to commit with category."
end

function __prs_status
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    if not test -f $session_dir/branches.txt
        echo "No PRs created yet."
        return 0
    end
    
    echo ""
    echo "Created PRs:"
    echo ""
    
    set -l index 1
    while read -l line
        if test -z "$line"; or test "$line" = "branches"
            continue
        end
        
        set -l branch (echo $line | awk '{print $1}')
        set -l base (echo $line | awk '{print $2}')
        set -l pr_url (echo $line | awk '{print $3}')
        
        set -l pr_status "OPEN"
        if test "$pr_url" = "local"
            set pr_status "LOCAL (not pushed)"
        else if git show-ref --verify --quiet refs/remotes/origin/$base
            set pr_status "OPEN"
        else
            set pr_status "NEEDS REBASE"
        end
        
        echo "  $index. $branch ($base) - $pr_status"
        if test -n "$pr_url"; and test "$pr_url" != "local"
            echo "     PR: $pr_url"
        end
        echo ""
        
        set index (math $index + 1)
    end < $session_dir/branches.txt
    
    set -l needs_rebase (grep "NEEDS REBASE" $session_dir/branches.txt 2>/dev/null)
    if test -n "$needs_rebase"
        echo "Run 'prs rebase-chain' to update dependent PRs"
    end
end

function __prs_rebase_chain
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    set -l skip_confirm 0
    for arg in $argv
        if test "$arg" = "-y"; or test "$arg" = "--yes"
            set skip_confirm 1
        end
    end
    
    echo ""
    echo "Checking for merged PRs..."
    echo ""
    
    set -l main_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if test -z "$main_branch"
        set main_branch "main"
    end
    
    set -l merged_branches
    while read -l line
        if test -z "$line"; or test "$line" = "branches"
            continue
        end
        
        set -l branch (echo $line | awk '{print $1}')
        set -l base (echo $line | awk '{print $2}')
        
        if not git show-ref --verify --quiet refs/remotes/origin/$branch
            set -a merged_branches $branch
        end
    end < $session_dir/branches.txt
    
    if test -z "$merged_branches"
        echo "No merged PRs found."
        return 0
    end
    
    for merged in $merged_branches
        echo "Detected merged PR: $merged"
    end
    echo ""
    
    set -l dependent_branches
    while read -l line
        if test -z "$line"; or test "$line" = "branches"
            continue
        end
        
        set -l branch (echo $line | awk '{print $1}')
        set -l base (echo $line | awk '{print $2}')
        set -l pr_url (echo $line | awk '{print $3}')
        
        if contains $base $merged_branches
            set -a dependent_branches "$branch:$base:$pr_url"
        end
    end < $session_dir/branches.txt
    
    if test -z "$dependent_branches"
        echo "No dependent PRs to rebase."
        return 0
    end
    
    echo "Dependent PRs to rebase:"
    for dep in $dependent_branches
        set -l branch (string split ":" $dep)[1]
        echo "  - $branch → $main_branch"
    end
    echo ""
    
    for dep in $dependent_branches
        set -l branch (string split ":" $dep)[1]
        set -l old_base (string split ":" $dep)[2]
        set -l pr_url (string split ":" $dep)[3]
        
        echo "Will run: git checkout $branch"
        echo "Will run: git rebase --onto $main_branch $old_base"
        echo "Will run: git push --force-with-lease origin $branch"
        
        if test -n "$pr_url"
            set -l pr_number (string match -r '/pull/(\d+)' $pr_url | tail -n1)
            if test -n "$pr_number"
                echo "Will run: gh pr edit $pr_number --base $main_branch"
            end
        end
    end
    echo ""
    
    if test $skip_confirm -eq 0
        read -P "Rebase? (Y/n): " confirm
        if test "$confirm" = "n"
            return 1
        end
    end
    
    for dep in $dependent_branches
        set -l branch (string split ":" $dep)[1]
        set -l old_base (string split ":" $dep)[2]
        set -l pr_url (string split ":" $dep)[3]
        
        echo ""
        echo "▶ git checkout $branch"
        git checkout $branch
        
        echo "▶ git rebase --onto $main_branch $old_base"
        if not git rebase --onto $main_branch $old_base
            echo "Rebase failed. Resolve conflicts and run 'git rebase --continue'"
            return 1
        end
        
        echo "▶ git push --force-with-lease origin $branch"
        git push --force-with-lease origin $branch
        
        if test -n "$pr_url"
            set -l pr_number (string match -r '/pull/(\d+)' $pr_url | tail -n1)
            if test -n "$pr_number"
                echo "▶ gh pr edit $pr_number --base $main_branch"
                gh pr edit $pr_number --base $main_branch
            end
        end
        
        echo ""
        echo "Rebase complete! PR now targets $main_branch."
    end
end

function __prs_undo
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    set -l skip_confirm 0
    for arg in $argv
        if test "$arg" = "-y"; or test "$arg" = "--yes"
            set skip_confirm 1
        end
    end
    
    if not test -f $session_dir/branches.txt
        echo "No PRs to undo."
        return 0
    end
    
    set -l last_branch (tail -n 1 $session_dir/branches.txt)
    if test -z "$last_branch"; or test "$last_branch" = "branches"
        echo "No PRs to undo."
        return 0
    end
    
    set -l branch (echo $last_branch | awk '{print $1}')
    set -l pr_url (echo $last_branch | awk '{print $3}')
    
    echo ""
    echo "Delete PR: $branch"
    if test -n "$pr_url"
        echo "PR URL: $pr_url"
    end
    
    if test $skip_confirm -eq 0
        read -P "Confirm deletion? (y/N): " confirm
        if test "$confirm" != "y"
            return 1
        end
    end
    
    if test -n "$pr_url"
        set -l pr_number (string match -r '/pull/(\d+)' $pr_url | tail -n1)
        if test -n "$pr_number"
            gh pr close $pr_number
        end
    end
    
    git push origin --delete $branch 2>/dev/null
    git branch -D $branch 2>/dev/null
    
    sed -i '' -e '$d' $session_dir/branches.txt
    
    echo "PR deleted."
end

function __prs_reset
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session. Run 'prs init' first."
        return 1
    end
    
    set -l skip_confirm 0
    for arg in $argv
        if test "$arg" = "-y"; or test "$arg" = "--yes"
            set skip_confirm 1
        end
    end
    
    echo ""
    echo "This will delete ALL created PRs and branches."
    
    if test $skip_confirm -eq 0
        read -P "Confirm reset? (y/N): " confirm
        if test "$confirm" != "y"
            return 1
        end
    end
    
    if test -f $session_dir/branches.txt
        while read -l line
            if test -z "$line"; or test "$line" = "branches"
                continue
            end
            
            set -l branch (echo $line | awk '{print $1}')
            set -l pr_url (echo $line | awk '{print $3}')
            
            if test -n "$pr_url"
                set -l pr_number (string match -r '/pull/(\d+)' $pr_url | tail -n1)
                if test -n "$pr_number"
                    gh pr close $pr_number 2>/dev/null
                end
            end
            
            git push origin --delete $branch 2>/dev/null
            git branch -D $branch 2>/dev/null
        end < $session_dir/branches.txt
    end
    
    rm -rf $session_dir
    
    echo "Session reset. All PRs deleted."
end

function __prs_finish
    set -l session_dir (__prs_session_dir)
    if not test -d $session_dir
        echo "Error: No active session."
        return 1
    end
    
    echo ""
    echo "Cleaning up session..."
    
    rm -rf $session_dir
    
    echo "Session finished."
end
