#!/bin/bash
#
# JuiceFS Quota Command Test Script
# Tests all quota subcommands and options using SQLite backend
#

# 启用错误跟踪
set -e
set -o pipefail

# Configuration
JFS_BIN="./juicefs"
META_URL="sqlite3://test_quota.db"
VOL_NAME="testvol"
MOUNT_POINT="/tmp/jfs_quota_test"
TEST_DIR="${MOUNT_POINT}/quota_test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# 错误处理函数
error_handler() {
    local line_no=$1
    local error_code=$2
    log_error "Error occurred at line $line_no (exit code: $error_code)"
}

trap 'error_handler ${LINENO} $?' ERR

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 获取当前行号
get_line_no() {
    echo "${BASH_LINENO[1]}"
}

# Test assertion functions
assert_success() {
    local test_name="$1"
    local cmd="$2"
    local line_no=$(get_line_no)
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    log_info "Running: $test_name [Line: $line_no]"
    log_debug "Command: $cmd"
    
    local output
    local exit_code=0
    output=$(eval "$cmd" 2>&1) || exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_info "✓ PASSED: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ FAILED: $test_name (Line: $line_no)"
        log_error "Command: $cmd"
        log_error "Exit code: $exit_code"
        log_error "Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_failure() {
    local test_name="$1"
    local cmd="$2"
    local line_no=$(get_line_no)
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    log_info "Running: $test_name (expecting failure) [Line: $line_no]"
    log_debug "Command: $cmd"
    
    local output
    local exit_code=0
    output=$(eval "$cmd" 2>&1) || exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_info "✓ PASSED: $test_name (failed as expected, exit code: $exit_code)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ FAILED: $test_name (Line: $line_no)"
        log_error "Expected failure but command succeeded"
        log_error "Command: $cmd"
        log_error "Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local test_name="$1"
    local cmd="$2"
    local expected="$3"
    local line_no=$(get_line_no)
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    log_info "Running: $test_name [Line: $line_no]"
    log_debug "Command: $cmd"
    log_debug "Expected to contain: $expected"
    
    local output
    local exit_code=0
    output=$(eval "$cmd" 2>&1) || exit_code=$?
    
    if [ $exit_code -eq 0 ] && echo "$output" | grep -q "$expected"; then
        log_info "✓ PASSED: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ FAILED: $test_name (Line: $line_no)"
        log_error "Command: $cmd"
        log_error "Exit code: $exit_code"
        log_error "Expected to contain: $expected"
        log_error "Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Setup function
setup() {
    log_info "Setting up test environment..."
    
    # Clean up any previous test artifacts
    cleanup
    
    # Build juicefs if not exists
    if [ ! -f "$JFS_BIN" ]; then
        log_info "Building juicefs..."
        make juicefs
    fi
    
    # Check juicefs binary
    if [ ! -f "$JFS_BIN" ]; then
        log_error "JuiceFS binary not found at $JFS_BIN"
        exit 1
    fi
    
    log_info "Using JuiceFS binary: $(realpath $JFS_BIN)"
    
    # Format filesystem
    log_info "Formatting JuiceFS with SQLite..."
    local output
    if ! output=$($JFS_BIN format "$META_URL" "$VOL_NAME" --trash-days 0 2>&1); then
        log_error "Failed to format filesystem"
        log_error "Output: $output"
        exit 1
    fi
    log_info "Format successful"
    
    # Create mount point
    mkdir -p "$MOUNT_POINT"
    
    # Mount filesystem
    log_info "Mounting JuiceFS to $MOUNT_POINT..."
    if ! output=$($JFS_BIN mount "$META_URL" "$MOUNT_POINT" -d 2>&1); then
        log_error "Failed to mount filesystem"
        log_error "Output: $output"
        exit 1
    fi
    
    # Wait for mount
    sleep 2
    
    # Verify mount
    if ! mount | grep -q "$MOUNT_POINT"; then
        log_error "Mount verification failed"
        exit 1
    fi
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    
    log_info "Setup complete!"
    log_info "Test directory: $TEST_DIR"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Unmount if mounted
    if mount | grep -q "$MOUNT_POINT" 2>/dev/null; then
        log_info "Unmounting $MOUNT_POINT..."
        $JFS_BIN umount "$MOUNT_POINT" 2>/dev/null || umount "$MOUNT_POINT" 2>/dev/null || true
        sleep 1
    fi
    
    # Remove mount point
    if [ -d "$MOUNT_POINT" ]; then
        rm -rf "$MOUNT_POINT"
    fi
    
    # Remove test database
    if [ -f "test_quota.db" ]; then
        rm -f test_quota.db
    fi
    
    # Remove storage directory (important for local storage)
    local storage_dir="$HOME/.juicefs/local/$VOL_NAME"
    if [ -d "$storage_dir" ]; then
        log_info "Removing storage directory: $storage_dir"
        rm -rf "$storage_dir"
    fi
    
    log_info "Cleanup complete!"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

#===============================================================================
# Test Suite: Directory Quota
#===============================================================================
test_dir_quota_set() {
    log_info "=== Testing Directory Quota Set ==="
    
    # 先创建测试目录（在挂载的文件系统内）
    mkdir -p "$TEST_DIR/dir1" "$TEST_DIR/dir2" "$TEST_DIR/dir3"
    
    # Test 1: Set capacity only (使用文件系统内的路径)
    assert_success "Set dir quota with capacity only" \
        "$JFS_BIN quota set $META_URL --path /quota_test/dir1 --capacity 1"
    
    # Test 2: Set inodes only
    assert_success "Set dir quota with inodes only" \
        "$JFS_BIN quota set $META_URL --path /quota_test/dir2 --inodes 100"
    
    # Test 3: Set both capacity and inodes
    assert_success "Set dir quota with capacity and inodes" \
        "$JFS_BIN quota set $META_URL --path /quota_test/dir3 --capacity 2 --inodes 200"
    
    # Test 4: Update existing quota
    assert_success "Update existing dir quota" \
        "$JFS_BIN quota set $META_URL --path /quota_test/dir1 --capacity 5"
    
    # Test 5: Create directory if not exists
    assert_success "Set quota with --create flag" \
        "$JFS_BIN quota set $META_URL --path /quota_test/newdir1 --capacity 1 --create"
    
    # Test 6: Set nested directory quota
    mkdir -p "$TEST_DIR/nested/subdir"
    assert_success "Set quota on nested directory" \
        "$JFS_BIN quota set $META_URL --path /quota_test/nested/subdir --capacity 1"
}

test_dir_quota_get() {
    log_info "=== Testing Directory Quota Get ==="
    
    # Setup: create a quota first
    mkdir -p "$TEST_DIR/gettest"
    $JFS_BIN quota set $META_URL --path /quota_test/gettest --capacity 10 --inodes 1000 2>/dev/null || true
    
    # Test 1: Get existing quota
    assert_contains "Get existing dir quota" \
        "$JFS_BIN quota get $META_URL --path /quota_test/gettest" \
        "gettest"
    
    # Test 2: Get non-existent quota (should fail with error)
    assert_failure "Get non-existent dir quota" \
        "$JFS_BIN quota get $META_URL --path /quota_test/noquota"
}

test_dir_quota_delete() {
    log_info "=== Testing Directory Quota Delete ==="
    
    # Setup: create a quota first
    mkdir -p "$TEST_DIR/deltest"
    $JFS_BIN quota set $META_URL --path /quota_test/deltest --capacity 1 2>/dev/null || true
    
    # Test 1: Delete existing quota
    assert_success "Delete existing dir quota" \
        "$JFS_BIN quota delete $META_URL --path /quota_test/deltest"
    
    # Test 2: Delete using 'del' alias
    mkdir -p "$TEST_DIR/deltest2"
    $JFS_BIN quota set $META_URL --path /quota_test/deltest2 --capacity 1 2>/dev/null || true
    assert_success "Delete quota using 'del' alias" \
        "$JFS_BIN quota del $META_URL --path /quota_test/deltest2"
    
    # Test 3: Delete non-existent quota (should fail)
    assert_failure "Delete non-existent dir quota" \
        "$JFS_BIN quota delete $META_URL --path /quota_test/noquota"
}

test_dir_quota_list() {
    log_info "=== Testing Directory Quota List ==="
    
    # Setup: create some quotas
    mkdir -p "$TEST_DIR/listtest1" "$TEST_DIR/listtest2"
    $JFS_BIN quota set $META_URL --path /quota_test/listtest1 --capacity 1 2>/dev/null || true
    $JFS_BIN quota set $META_URL --path /quota_test/listtest2 --inodes 100 2>/dev/null || true
    
    # Test 1: List all directory quotas
    local output
    output=$($JFS_BIN quota list $META_URL 2>&1) || true
    if echo "$output" | grep -q "listtest1"; then
        log_info "✓ PASSED: List all quotas contains listtest1"
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ FAILED: List all quotas does not contain listtest1"
        log_error "Output: $output"
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Test 2: List using 'ls' alias
    output=$($JFS_BIN quota ls $META_URL 2>&1) || true
    if echo "$output" | grep -q "listtest2"; then
        log_info "✓ PASSED: List quotas using 'ls' alias contains listtest2"
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ FAILED: List quotas using 'ls' alias does not contain listtest2"
        log_error "Output: $output"
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_dir_quota_check() {
    log_info "=== Testing Directory Quota Check ==="
    
    # Setup: create a quota on empty directory first
    mkdir -p "$TEST_DIR/checktest"
    $JFS_BIN quota set $META_URL --path /quota_test/checktest --capacity 100 --inodes 1000 2>/dev/null || true
    
    # Test 1: Check quota consistency on empty directory (should pass)
    assert_success "Check dir quota consistency on empty dir" \
        "$JFS_BIN quota check $META_URL --path /quota_test/checktest"
    
    # Note: --strict mode tests are skipped for now, will be tested after strict mode is fully supported
}

#===============================================================================
# Test Suite: User Quota
#===============================================================================
test_user_quota_set() {
    log_info "=== Testing User Quota Set ==="
    
    # Test 1: Set user quota with capacity only
    assert_success "Set user quota with capacity only" \
        "$JFS_BIN quota set $META_URL --uid 1001 --capacity 10"
    
    # Test 2: Set user quota with inodes only
    assert_success "Set user quota with inodes only" \
        "$JFS_BIN quota set $META_URL --uid 1002 --inodes 1000"
    
    # Test 3: Set user quota with both
    assert_success "Set user quota with capacity and inodes" \
        "$JFS_BIN quota set $META_URL --uid 1003 --capacity 20 --inodes 2000"
    
    # Test 4: Update existing user quota
    assert_success "Update existing user quota" \
        "$JFS_BIN quota set $META_URL --uid 1001 --capacity 50"
}

test_user_quota_get() {
    log_info "=== Testing User Quota Get ==="
    
    # Setup
    $JFS_BIN quota set $META_URL --uid 2001 --capacity 10 --inodes 100 2>/dev/null || true
    
    # Test 1: Get existing user quota
    assert_contains "Get existing user quota" \
        "$JFS_BIN quota get $META_URL --uid 2001" \
        "2001"
    
    # Test 2: Get non-existent user quota
    assert_success "Get non-existent user quota" \
        "$JFS_BIN quota get $META_URL --uid 9999"
}

test_user_quota_delete() {
    log_info "=== Testing User Quota Delete ==="
    
    # Setup
    $JFS_BIN quota set $META_URL --uid 3001 --capacity 1 2>/dev/null || true
    
    # Test 1: Delete existing user quota
    assert_success "Delete existing user quota" \
        "$JFS_BIN quota delete $META_URL --uid 3001"
    
    # Test 2: Delete non-existent user quota
    assert_success "Delete non-existent user quota" \
        "$JFS_BIN quota delete $META_URL --uid 9999"
}

#===============================================================================
# Test Suite: Group Quota
#===============================================================================
test_group_quota_set() {
    log_info "=== Testing Group Quota Set ==="
    
    # Test 1: Set group quota with capacity only
    assert_success "Set group quota with capacity only" \
        "$JFS_BIN quota set $META_URL --gid 100 --capacity 10"
    
    # Test 2: Set group quota with inodes only
    assert_success "Set group quota with inodes only" \
        "$JFS_BIN quota set $META_URL --gid 101 --inodes 1000"
    
    # Test 3: Set group quota with both
    assert_success "Set group quota with capacity and inodes" \
        "$JFS_BIN quota set $META_URL --gid 102 --capacity 20 --inodes 2000"
    
    # Test 4: Update existing group quota
    assert_success "Update existing group quota" \
        "$JFS_BIN quota set $META_URL --gid 100 --capacity 50"
}

test_group_quota_get() {
    log_info "=== Testing Group Quota Get ==="
    
    # Setup
    $JFS_BIN quota set $META_URL --gid 200 --capacity 10 --inodes 100 2>/dev/null || true
    
    # Test 1: Get existing group quota
    assert_contains "Get existing group quota" \
        "$JFS_BIN quota get $META_URL --gid 200" \
        "200"
    
    # Test 2: Get non-existent group quota
    assert_success "Get non-existent group quota" \
        "$JFS_BIN quota get $META_URL --gid 999"
}

test_group_quota_delete() {
    log_info "=== Testing Group Quota Delete ==="
    
    # Setup
    $JFS_BIN quota set $META_URL --gid 300 --capacity 1 2>/dev/null || true
    
    # Test 1: Delete existing group quota
    assert_success "Delete existing group quota" \
        "$JFS_BIN quota delete $META_URL --gid 300"
    
    # Test 2: Delete non-existent group quota
    assert_success "Delete non-existent group quota" \
        "$JFS_BIN quota delete $META_URL --gid 999"
}

#===============================================================================
# Test Suite: Error Cases and Validation
#===============================================================================
test_error_cases() {
    log_info "=== Testing Error Cases ==="
    
    # Test 1: Cannot specify both --uid and --gid
    assert_failure "Cannot specify both --uid and --gid" \
        "$JFS_BIN quota set $META_URL --uid 1001 --gid 100 --capacity 1"
    
    # Test 2: Cannot specify both --uid and --path
    assert_failure "Cannot specify both --uid and --path" \
        "$JFS_BIN quota set $META_URL --uid 1001 --path $TEST_DIR --capacity 1"
    
    # Test 3: Cannot specify both --gid and --path
    assert_failure "Cannot specify both --gid and --path" \
        "$JFS_BIN quota set $META_URL --gid 100 --path $TEST_DIR --capacity 1"
    
    # Test 4: UID cannot be 0
    assert_failure "UID cannot be 0" \
        "$JFS_BIN quota set $META_URL --uid 0 --capacity 1"
    
    # Test 5: GID cannot be 0
    assert_failure "GID cannot be 0" \
        "$JFS_BIN quota set $META_URL --gid 0 --capacity 1"
    
    # Test 6: Missing path/uid/gid for set command
    assert_failure "Missing path/uid/gid for set" \
        "$JFS_BIN quota set $META_URL --capacity 1"
    
    # Test 7: Missing path/uid/gid for get command
    assert_failure "Missing path/uid/gid for get" \
        "$JFS_BIN quota get $META_URL"
    
    # Test 8: Missing path/uid/gid for delete command
    assert_failure "Missing path/uid/gid for delete" \
        "$JFS_BIN quota delete $META_URL"
}

#===============================================================================
# Test Suite: Quota Enforcement
#===============================================================================
test_quota_enforcement() {
    log_info "=== Testing Quota Enforcement ==="
    
    # Test 1: Directory space quota enforcement
    mkdir -p "$TEST_DIR/enforce_space"
    $JFS_BIN quota set $META_URL --path /quota_test/enforce_space --capacity 1 2>/dev/null || true
    
    # Create a file that should succeed (under 1GiB)
    assert_success "Create file under space quota" \
        "dd if=/dev/zero of=$TEST_DIR/enforce_space/smallfile bs=1M count=10"
    
    log_info "Note: Testing hard quota enforcement requires careful setup and may vary by system"
    
    # Test 2: Directory inodes quota enforcement
    mkdir -p "$TEST_DIR/enforce_inodes"
    $JFS_BIN quota set $META_URL --path /quota_test/enforce_inodes --inodes 5 2>/dev/null || true
    
    # Create files within quota
    assert_success "Create files within inodes quota" \
        "touch $TEST_DIR/enforce_inodes/file1 $TEST_DIR/enforce_inodes/file2"
    
    # Test 3: User quota setup
    $JFS_BIN quota set $META_URL --uid 5000 --capacity 100 --inodes 1000 2>/dev/null || true
    assert_success "Set user quota for enforcement test" \
        "$JFS_BIN quota get $META_URL --uid 5000"
    
    # Test 4: Group quota setup
    $JFS_BIN quota set $META_URL --gid 500 --capacity 100 --inodes 1000 2>/dev/null || true
    assert_success "Set group quota for enforcement test" \
        "$JFS_BIN quota get $META_URL --gid 500"
}

#===============================================================================
# Test Suite: Mixed Quota Types
#===============================================================================
test_mixed_quota_types() {
    log_info "=== Testing Mixed Quota Types ==="
    
    # Setup: Create all three types of quotas
    mkdir -p "$TEST_DIR/mixed"
    $JFS_BIN quota set $META_URL --path /quota_test/mixed --capacity 100 2>/dev/null || true
    $JFS_BIN quota set $META_URL --uid 6000 --capacity 100 2>/dev/null || true
    $JFS_BIN quota set $META_URL --gid 600 --capacity 100 2>/dev/null || true
    
    # Test: List should show all types (if supported)
    assert_contains "List quotas with mixed types" \
        "$JFS_BIN quota list $META_URL" \
        "mixed"
    
    # Verify each type exists
    assert_success "Verify dir quota exists" \
        "$JFS_BIN quota get $META_URL --path /quota_test/mixed"
    assert_success "Verify user quota exists" \
        "$JFS_BIN quota get $META_URL --uid 6000"
    assert_success "Verify group quota exists" \
        "$JFS_BIN quota get $META_URL --gid 600"
}

#===============================================================================
# Test Suite: Quota Check and Repair
#===============================================================================
test_quota_check_repair() {
    log_info "=== Testing Quota Check and Repair ==="
    
    # Setup: Create quota and files
    mkdir -p "$TEST_DIR/check_repair"
    $JFS_BIN quota set $META_URL --path /quota_test/check_repair --capacity 100 --inodes 1000 2>/dev/null || true
    
    # Create some files
    echo "file1" > "$TEST_DIR/check_repair/file1.txt"
    echo "file2" > "$TEST_DIR/check_repair/file2.txt"
    mkdir -p "$TEST_DIR/check_repair/subdir"
    echo "file3" > "$TEST_DIR/check_repair/subdir/file3.txt"
    
    # Test 1: Check with repair (also verifies check works)
    assert_success "Check quota with repair" \
        "$JFS_BIN quota check $META_URL --path /quota_test/check_repair --repair"
    
    # Note: --strict mode tests are skipped for now
    
    # Test 4: Check specific user/group quotas
    $JFS_BIN quota set $META_URL --uid 7000 --capacity 100 2>/dev/null || true
    $JFS_BIN quota set $META_URL --gid 700 --capacity 100 2>/dev/null || true
    
    # Note: quota check requires --path, --uid, or --gid parameter
    # Check specific user quota with repair
    assert_success "Check and repair user quota" \
        "$JFS_BIN quota check $META_URL --uid 7000 --repair"
    
    # Check specific group quota with repair
    assert_success "Check and repair group quota" \
        "$JFS_BIN quota check $META_URL --gid 700 --repair"
}

#===============================================================================
# Test Suite: Edge Cases
#===============================================================================
test_edge_cases() {
    log_info "=== Testing Edge Cases ==="
    
    # Test 1: Very large capacity value
    mkdir -p "$TEST_DIR/large_cap"
    assert_success "Set quota with large capacity" \
        "$JFS_BIN quota set $META_URL --path /quota_test/large_cap --capacity 1048576"
    
    # Test 2: Very large inodes value
    mkdir -p "$TEST_DIR/large_inodes"
    assert_success "Set quota with large inodes" \
        "$JFS_BIN quota set $META_URL --path /quota_test/large_inodes --inodes 1000000000"
    
    # Test 3: Update quota to 0 (unlimited)
    mkdir -p "$TEST_DIR/unlimited"
    $JFS_BIN quota set $META_URL --path /quota_test/unlimited --capacity 10 2>/dev/null || true
    assert_success "Update quota to unlimited (0)" \
        "$JFS_BIN quota set $META_URL --path /quota_test/unlimited --capacity 0"
    
    # Test 4: Nested directories with different quotas
    mkdir -p "$TEST_DIR/parent/child/grandchild"
    $JFS_BIN quota set $META_URL --path /quota_test/parent --capacity 100 2>/dev/null || true
    $JFS_BIN quota set $META_URL --path /quota_test/parent/child --capacity 50 2>/dev/null || true
    $JFS_BIN quota set $META_URL --path /quota_test/parent/child/grandchild --capacity 25 2>/dev/null || true
    
    assert_success "Get nested quota - parent" \
        "$JFS_BIN quota get $META_URL --path /quota_test/parent"
    assert_success "Get nested quota - child" \
        "$JFS_BIN quota get $META_URL --path /quota_test/parent/child"
    assert_success "Get nested quota - grandchild" \
        "$JFS_BIN quota get $META_URL --path /quota_test/parent/child/grandchild"
}

#===============================================================================
# Main Test Runner
#===============================================================================
run_all_tests() {
    log_info "Starting JuiceFS Quota Tests..."
    log_info "================================"
    
    # Directory Quota Tests
    test_dir_quota_set
    test_dir_quota_get
    test_dir_quota_delete
    test_dir_quota_list
    test_dir_quota_check
    
    # User Quota Tests
    test_user_quota_set
    test_user_quota_get
    test_user_quota_delete
    
    # Group Quota Tests
    test_group_quota_set
    test_group_quota_get
    test_group_quota_delete
    
    # Error Cases
    test_error_cases
    
    # Quota Enforcement
    test_quota_enforcement
    
    # Mixed Types
    test_mixed_quota_types
    
    # Check and Repair
    test_quota_check_repair
    
    # Edge Cases
    test_edge_cases
    
    # Print summary
    log_info "================================"
    log_info "Test Summary:"
    log_info "  Total:  $TESTS_TOTAL"
    log_info "  Passed: $TESTS_PASSED"
    log_info "  Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_info "All tests passed! ✓"
        return 0
    else
        log_error "Some tests failed! ✗"
        return 1
    fi
}

# Run tests
setup
run_all_tests
exit $?
