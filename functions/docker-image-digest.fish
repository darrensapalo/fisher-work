function docker_image_digest --description "Get the digest of a Docker image"
    # Check if image name is provided
    if test (count $argv) -eq 0
        echo "Usage: docker_image_digest <image_name>"
        echo "Example: docker_image_digest logos:latest"
        return 1
    end

    set image_name $argv[1]
    
    # Check if image exists
    if not docker image inspect $image_name >/dev/null 2>&1
        echo "Error: Image '$image_name' not found"
        return 1
    end

    # Get image details
    set digest (docker image inspect $image_name --format '{{.RepoDigests}}')
    set created (docker image inspect $image_name --format '{{.Created}}')
    set size (docker image inspect $image_name --format '{{.Size}}')
    
    # Format size in human-readable format
    set size_mb (math -s2 $size / 1024 / 1024)
    
    # Print results
    echo "Image: $image_name"
    echo "Digest: $digest"
    echo "Created: $created"
    echo "Size: $size_mb MB"
end 