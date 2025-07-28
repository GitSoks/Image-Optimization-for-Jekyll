#!/usr/bin/env bash
#
# Image Optimization Script for Jekyll Site with WebP Conversion
#
# This script optimizes images in assets/img/posts for better web performance
# - Converts images to WebP format for better compression
# - Updates markdown files to reference new WebP images
# - Resizes images to appropriate dimensions for web viewing
# - Creates backups of original images
# - Supports PNG, JPG, JPEG formats
#
# Requirements: imagemagick with WebP support
#
# Usage: ./tools/optimize-images.sh [options]

set -eu

IMAGES_DIR="assets/img/posts"
BACKUP_DIR="assets/img/posts/.originals"
POSTS_DIR="_posts"
MAX_WIDTH=1200
MAX_HEIGHT=800
WEBP_QUALITY=80
DRY_RUN=false
FORCE=false
CONVERT_TO_WEBP=true

help() {
  echo "Optimize images for web performance with WebP conversion"
  echo
  echo "Usage:"
  echo
  echo "   bash $0 [options]"
  echo
  echo "Options:"
  echo "     -w, --width <pixels>     Maximum width (default: $MAX_WIDTH)"
  echo "     -h, --height <pixels>    Maximum height (default: $MAX_HEIGHT)"
  echo "     -q, --quality <1-100>    WebP quality (default: $WEBP_QUALITY)"
  echo "     -n, --dry-run            Show what would be done without making changes"
  echo "     -f, --force              Overwrite existing optimized images"
  echo "     --no-webp                Keep original format instead of converting to WebP"
  echo "     --help                   Print this information"
  echo
  echo "Examples:"
  echo "   $0                       # Optimize all images with WebP conversion"
  echo "   $0 --width 800           # Set max width to 800px"
  echo "   $0 --dry-run             # Preview what would be optimized"
  echo "   $0 --no-webp             # Optimize without WebP conversion"
  echo "   $0 --force               # Re-optimize all images"
}

check_dependencies() {
  if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
    echo "Error: ImageMagick is required but not installed."
    echo "Install it with:"
    echo "  Ubuntu/Debian: sudo apt-get install imagemagick"
    echo "  macOS: brew install imagemagick"
    echo "  Or visit: https://imagemagick.org/script/download.php"
    exit 1
  fi
  
  # Check WebP support if converting to WebP
  if [ "$CONVERT_TO_WEBP" = true ]; then
    if command -v magick >/dev/null 2>&1; then
      if ! magick -list format | grep -q "WEBP"; then
        echo "Error: ImageMagick does not support WebP format."
        echo "Install ImageMagick with WebP support or use --no-webp option."
        exit 1
      fi
    else
      if ! convert -list format | grep -q "WEBP"; then
        echo "Error: ImageMagick does not support WebP format."
        echo "Install ImageMagick with WebP support or use --no-webp option."
        exit 1
      fi
    fi
  fi
}

get_image_info() {
  local file="$1"
  if command -v magick >/dev/null 2>&1; then
    magick identify -format "%wx%h %b" "$file" 2>/dev/null
  else
    identify -format "%wx%h %b" "$file" 2>/dev/null
  fi
}

get_webp_filename() {
  local original_file="$1"
  local dir=$(dirname "$original_file")
  local filename=$(basename "$original_file")
  local name_without_ext="${filename%.*}"
  echo "$dir/$name_without_ext.webp"
}

update_markdown_references() {
  local original_file="$1"
  local webp_file="$2"
  
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would update markdown files to reference WebP image"
    return
  fi
  
  # Get just the filenames (not full paths)
  local original_filename=$(basename "$original_file")
  local webp_filename=$(basename "$webp_file")
  
  # Also get the directory name for more specific matching
  local dir_name=$(basename "$(dirname "$original_file")")
  
  # Find and update markdown files
  local updated_files=0
  while IFS= read -r -d '' post_file; do
    # Check if the file contains references to this image
    if grep -q "$original_filename" "$post_file"; then
      # Create backup of markdown file
      cp "$post_file" "$post_file.bak"
      
      # Update all references to this filename
      sed "s|$original_filename|$webp_filename|g" "$post_file.bak" > "$post_file"
      
      # Check if changes were made
      if ! diff -q "$post_file.bak" "$post_file" >/dev/null 2>&1; then
        echo "    Updated references in: $post_file"
        updated_files=$((updated_files + 1))
      fi
      
      # Remove backup
      rm "$post_file.bak"
    fi
  done < <(find "$POSTS_DIR" -name "*.md" -print0 2>/dev/null || true)
  
  if [ "$updated_files" -gt 0 ]; then
    echo "    Updated $updated_files markdown file(s)"
  fi
}

optimize_image() {
  local input_file="$1"
  local backup_file="$2"
  
  echo "Processing: $input_file"
  
  # Get original dimensions and size
  local info=$(get_image_info "$input_file")
  if [ $? -ne 0 ] || [ -z "$info" ]; then
    echo "  ⚠ Warning: Could not read image info (possibly corrupted)"
    return 1
  fi
  
  local original_size=$(echo "$info" | awk '{print $2}')
  local dimensions=$(echo "$info" | awk '{print $1}')
  
  echo "  Original: $dimensions ($original_size)"
  
  if [ "$DRY_RUN" = true ]; then
    if [ "$CONVERT_TO_WEBP" = true ]; then
      local webp_file=$(get_webp_filename "$input_file")
      echo "  [DRY RUN] Would convert to WebP: $webp_file"
      echo "  [DRY RUN] Would resize and compress image"
      echo "  [DRY RUN] Would update markdown references"
    else
      echo "  [DRY RUN] Would resize and compress image"
    fi
    return
  fi
  
  # Create backup if it doesn't exist
  if [ ! -f "$backup_file" ]; then
    mkdir -p "$(dirname "$backup_file")"
    cp "$input_file" "$backup_file"
    echo "  Backup created: $backup_file"
  fi
  
  # Determine output file
  local output_file="$input_file"
  if [ "$CONVERT_TO_WEBP" = true ]; then
    output_file=$(get_webp_filename "$input_file")
  fi
  
  # Optimize the image
  local optimize_cmd
  if [ "$CONVERT_TO_WEBP" = true ]; then
    if command -v magick >/dev/null 2>&1; then
      optimize_cmd="magick \"$input_file\" -resize \"${MAX_WIDTH}x${MAX_HEIGHT}>\" -quality \"$WEBP_QUALITY\" -strip \"$output_file\""
    else
      optimize_cmd="convert \"$input_file\" -resize \"${MAX_WIDTH}x${MAX_HEIGHT}>\" -quality \"$WEBP_QUALITY\" -strip \"$output_file\""
    fi
  else
    if command -v magick >/dev/null 2>&1; then
      optimize_cmd="magick \"$input_file\" -resize \"${MAX_WIDTH}x${MAX_HEIGHT}>\" -quality \"$WEBP_QUALITY\" -strip \"$output_file\""
    else
      optimize_cmd="convert \"$input_file\" -resize \"${MAX_WIDTH}x${MAX_HEIGHT}>\" -quality \"$WEBP_QUALITY\" -strip \"$output_file\""
    fi
  fi
  
  if ! eval $optimize_cmd 2>/dev/null; then
    echo "  ⚠ Error: Failed to optimize image (possibly corrupted)"
    return 1
  fi
  
  # Get new size
  local new_info=$(get_image_info "$output_file")
  if [ $? -ne 0 ] || [ -z "$new_info" ]; then
    echo "  ⚠ Warning: Could not read optimized image info"
    return 1
  fi
  
  local new_size=$(echo "$new_info" | awk '{print $2}')
  local new_dimensions=$(echo "$new_info" | awk '{print $1}')
  
  if [ "$CONVERT_TO_WEBP" = true ]; then
    echo "  WebP: $new_dimensions ($new_size)"
  else
    echo "  Optimized: $new_dimensions ($new_size)"
  fi
  
  # Calculate savings
  local original_bytes=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null || echo "0")
  local new_bytes=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null || echo "0")
  
  if [ "$original_bytes" -gt 0 ] && [ "$new_bytes" -gt 0 ]; then
    local savings=$((100 - (new_bytes * 100 / original_bytes)))
    echo "  Savings: ${savings}%"
  fi
  
  # Update markdown files if converted to WebP
  if [ "$CONVERT_TO_WEBP" = true ] && [ "$output_file" != "$input_file" ]; then
    update_markdown_references "$input_file" "$output_file"
    
    # Remove original file after successful conversion
    if [ -f "$output_file" ]; then
      rm "$input_file"
      echo "  Removed original: $input_file"
    fi
  fi
  
  echo "  ✓ Optimized successfully"
}

should_optimize() {
  local file="$1"
  local backup_file="$2"
  
  # Always optimize if force mode is enabled
  if [ "$FORCE" = true ]; then
    return 0
  fi
  
  # Optimize if no backup exists (first time)
  if [ ! -f "$backup_file" ]; then
    return 0
  fi
  
  # Check if original file is newer than backup
  if [ "$file" -nt "$backup_file" ]; then
    return 0
  fi
  
  # If converting to WebP, check if WebP version exists
  if [ "$CONVERT_TO_WEBP" = true ]; then
    local webp_file=$(get_webp_filename "$file")
    if [ ! -f "$webp_file" ]; then
      return 0
    fi
  fi
  
  # Don't optimize if already optimized
  return 1
}

main() {
  check_dependencies
  
  if [ ! -d "$IMAGES_DIR" ]; then
    echo "Error: Images directory '$IMAGES_DIR' not found"
    exit 1
  fi
  
  echo "Starting image optimization with WebP conversion..."
  echo "Settings:"
  echo "  Max dimensions: ${MAX_WIDTH}x${MAX_HEIGHT}"
  if [ "$CONVERT_TO_WEBP" = true ]; then
    echo "  WebP quality: ${WEBP_QUALITY}%"
    echo "  Convert to WebP: Yes"
  else
    echo "  Quality: ${WEBP_QUALITY}%"
    echo "  Convert to WebP: No"
  fi
  echo "  Dry run: $DRY_RUN"
  echo "  Force: $FORCE"
  echo
  
  local count=0
  local optimized=0
  local errors=0
  
  # Find all image files
  while IFS= read -r -d '' file; do
    count=$((count + 1))
    
    # Calculate relative path for backup
    local rel_path="${file#$IMAGES_DIR/}"
    local backup_file="$BACKUP_DIR/$rel_path"
    
    if should_optimize "$file" "$backup_file"; then
      if optimize_image "$file" "$backup_file"; then
        optimized=$((optimized + 1))
      else
        errors=$((errors + 1))
        echo "  ✗ Failed to optimize"
      fi
      echo
    else
      echo "Skipping: $file (already optimized)"
    fi
    
  done < <(find "$IMAGES_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) ! -path "*/.originals/*" -print0)
  
  echo "Summary:"
  echo "  Total images found: $count"
  echo "  Images optimized: $optimized"
  echo "  Images with errors: $errors"
  echo "  Images skipped: $((count - optimized - errors))"
  
  if [ "$optimized" -gt 0 ] && [ "$DRY_RUN" = false ]; then
    echo
    if [ "$CONVERT_TO_WEBP" = true ]; then
      echo "✓ Image optimization with WebP conversion completed!"
    else
      echo "✓ Image optimization completed!"
    fi
    echo "Original images backed up to: $BACKUP_DIR"
    if [ "$CONVERT_TO_WEBP" = true ]; then
      echo "Markdown files updated to reference WebP images"
    fi
    echo
    echo "To revert all optimizations:"
    echo "  ./tools/optimize-images.sh --restore"
  fi
}

restore_images() {
  if [ ! -d "$BACKUP_DIR" ]; then
    echo "No backups found in $BACKUP_DIR"
    exit 1
  fi
  
  echo "Restoring original images from backups..."
  echo "This will also revert any WebP conversions and markdown changes."
  
  local count=0
  local markdown_reverted=0
  
  while IFS= read -r -d '' backup_file; do
    local rel_path="${backup_file#$BACKUP_DIR/}"
    local original_file="$IMAGES_DIR/$rel_path"
    local webp_file=$(get_webp_filename "$original_file")
    
    # Restore original file
    if [ -f "$backup_file" ]; then
      mkdir -p "$(dirname "$original_file")"
      cp "$backup_file" "$original_file"
      echo "Restored: $original_file"
      count=$((count + 1))
      
      # Remove WebP file if it exists
      if [ -f "$webp_file" ]; then
        rm "$webp_file"
        echo "Removed WebP: $webp_file"
        
        # Revert markdown references from WebP back to original (using filenames)
        local original_filename=$(basename "$original_file")
        local webp_filename=$(basename "$webp_file")
        
        while IFS= read -r -d '' post_file; do
          if grep -q "$webp_filename" "$post_file"; then
            # Create backup of markdown file
            cp "$post_file" "$post_file.bak"
            
            # Revert the reference
            sed "s|$webp_filename|$original_filename|g" "$post_file.bak" > "$post_file"
            
            # Check if changes were made
            if ! diff -q "$post_file.bak" "$post_file" >/dev/null 2>&1; then
              echo "  Reverted references in: $post_file"
              markdown_reverted=$((markdown_reverted + 1))
            fi
            
            # Remove backup
            rm "$post_file.bak"
          fi
        done < <(find "$POSTS_DIR" -name "*.md" -print0 2>/dev/null || true)
      fi
    fi
  done < <(find "$BACKUP_DIR" -type f -print0)
  
  echo "Restored $count images from backups"
  if [ "$markdown_reverted" -gt 0 ]; then
    echo "Reverted markdown references in $markdown_reverted file(s)"
  fi
}

# Parse command line arguments
while (($#)); do
  case $1 in
  -w | --width)
    MAX_WIDTH="$2"
    shift 2
    ;;
  -h | --height)
    MAX_HEIGHT="$2"
    shift 2
    ;;
  -q | --quality)
    WEBP_QUALITY="$2"
    shift 2
    ;;
  -n | --dry-run)
    DRY_RUN=true
    shift
    ;;
  -f | --force)
    FORCE=true
    shift
    ;;
  --no-webp)
    CONVERT_TO_WEBP=false
    shift
    ;;
  --restore)
    restore_images
    exit 0
    ;;
  --help)
    help
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    help
    exit 1
    ;;
  esac
done

main
