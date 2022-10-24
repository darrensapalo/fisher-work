# This allows you to show active fish_user_paths
function fish-view-paths
    echo $fish_user_paths | tr " " "\n" | nl
end
