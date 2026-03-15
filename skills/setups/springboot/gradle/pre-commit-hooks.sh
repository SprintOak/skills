#!/usr/bin/env bash
# =============================================================================
# Spring Boot Code Quality Setup Script
# Configures Checkstyle, SpotlessApply, and Pre-commit Hooks for Gradle projects
# Copyright (c) Skills by SprintOak. All rights reserved.
# =============================================================================

set -euo pipefail

# ─── Colors & Formatting ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Constants ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOTLESS_VERSION="6.25.0"
CHECKSTYLE_VERSION="10.12.4"
REMOTE_BASE="https://sprintoak.com/skills/setups/springboot/gradle"

SRC_GRADLE_DIR="${SCRIPT_DIR}/gradle-files"
SRC_HOOKS_DIR="${SCRIPT_DIR}/pre-commit-hooks"

# ─── Logging Helpers ─────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${RESET}    $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET}   $*" >&2; }
log_step()    { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; }
log_skip()    { echo -e "${YELLOW}[SKIP]${RESET}    $*"; }

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

${BOLD}Usage:${RESET}
  $(basename "$0") [OPTIONS] [PROJECT_DIR]

${BOLD}Description:${RESET}
  Sets up Checkstyle, SpotlessApply (Google Java Format), and pre-commit git hooks
  for a Spring Boot Gradle project. Idempotent — safe to run multiple times.

${BOLD}Arguments:${RESET}
  PROJECT_DIR       Root of the Spring Boot project (default: current directory)

${BOLD}Options:${RESET}
  -h, --help        Show this help message
  -d, --dry-run     Preview changes without modifying anything
      --no-build    Skip the Gradle build step

${BOLD}Examples:${RESET}
  $(basename "$0")                         # Setup in current directory
  $(basename "$0") /path/to/project        # Setup in specified directory
  $(basename "$0") --dry-run .             # Preview what would change
  $(basename "$0") --no-build /my/project  # Configure without running build

EOF
    exit 0
}

# ─── Parse Arguments ─────────────────────────────────────────────────────────
DRY_RUN=false
NO_BUILD=false
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)      usage ;;
        -d|--dry-run)   DRY_RUN=true; shift ;;
        --no-build)     NO_BUILD=true; shift ;;
        -*)             log_error "Unknown option: $1"; usage ;;
        *)              PROJECT_DIR="$1"; shift ;;
    esac
done

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# ─── Declare globals (populated during detect_project) ───────────────────────
BUILD_FILE=""
BUILD_DSL=""
GRADLE_CMD=""
HAS_EXISTING_SPOTLESS=false   # project already has spotless configured
HAS_EXISTING_CHECKSTYLE=false # project already has checkstyle configured


# ─── Step 0: Validate source files (auto-download if missing) ────────────────
validate_source_files() {
    log_step "Validating setup source files"

    local needs_download=false
    for f in \
        "${SRC_GRADLE_DIR}/checkstyle.gradle" \
        "${SRC_GRADLE_DIR}/spotless.gradle" \
        "${SRC_GRADLE_DIR}/pre-commit.gradle" \
        "${SRC_HOOKS_DIR}/pre-commit" \
        "${SRC_HOOKS_DIR}/checkstyles.xml"; do
        [[ ! -f "$f" ]] && needs_download=true && break
    done

    if [[ "$needs_download" == "true" ]]; then
        log_info "Source files not found locally — downloading from remote..."
        local tmp_dir
        tmp_dir="$(mktemp -d)"
        mkdir -p "$tmp_dir/gradle-files" "$tmp_dir/pre-commit-hooks"
        for rf in \
            gradle-files/checkstyle.gradle \
            gradle-files/spotless.gradle \
            gradle-files/pre-commit.gradle \
            pre-commit-hooks/pre-commit \
            pre-commit-hooks/checkstyles.xml; do
            curl -fsSL "${REMOTE_BASE}/${rf}" -o "${tmp_dir}/${rf}"
        done
        SRC_GRADLE_DIR="${tmp_dir}/gradle-files"
        SRC_HOOKS_DIR="${tmp_dir}/pre-commit-hooks"
        log_success "Source files downloaded"
    fi
    log_success "All source files present"
}

# ─── Step 0: Check prerequisites ─────────────────────────────────────────────
check_prerequisites() {
    log_step "Checking prerequisites"

    if ! command -v java &>/dev/null; then
        log_error "Java not found. Install Java 17+ and ensure it is in PATH."
        exit 1
    fi
    local java_version
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    log_info "Java: ${java_version}"

    if ! command -v git &>/dev/null; then
        log_error "Git not found. Install git and ensure it is in PATH."
        exit 1
    fi

    if ! git -C "${PROJECT_DIR}" rev-parse --git-dir &>/dev/null; then
        log_error "${PROJECT_DIR} is not a git repository."
        log_info "Initialize with: git -C \"${PROJECT_DIR}\" init"
        exit 1
    fi

    if ! command -v python3 &>/dev/null; then
        log_error "python3 not found. Required to safely patch build.gradle."
        exit 1
    fi

    log_success "Prerequisites satisfied"
}

# ─── Step 0: Detect project type ─────────────────────────────────────────────
detect_project() {
    log_step "Detecting project"

    if [[ -f "${PROJECT_DIR}/build.gradle" ]]; then
        BUILD_FILE="${PROJECT_DIR}/build.gradle"
        BUILD_DSL="groovy"
        log_info "Build file: build.gradle (Groovy DSL)"
    elif [[ -f "${PROJECT_DIR}/build.gradle.kts" ]]; then
        BUILD_FILE="${PROJECT_DIR}/build.gradle.kts"
        BUILD_DSL="kotlin"
        log_info "Build file: build.gradle.kts (Kotlin DSL)"
    else
        log_error "No build.gradle or build.gradle.kts found in: ${PROJECT_DIR}"
        exit 1
    fi

    if [[ -f "${PROJECT_DIR}/gradlew" ]]; then
        GRADLE_CMD="${PROJECT_DIR}/gradlew"
        log_info "Gradle: ./gradlew (wrapper)"
    elif command -v gradle &>/dev/null; then
        GRADLE_CMD="gradle"
        log_warn "Gradle wrapper not found — using system gradle"
    else
        log_error "No Gradle wrapper or system gradle found."
        exit 1
    fi

    # Detect if spotless is already configured in the project — if so, skip adding our
    # spotless.gradle to avoid "Multiple steps with same name" conflicts
    if grep -qE "spotless\s*\{|id[[:space:]]+['\"]com\.diffplug\.spotless|apply plugin.*spotless" "${BUILD_FILE}" 2>/dev/null \
        || (find "${PROJECT_DIR}/gradle" -name "*.gradle" -o -name "*.gradle.kts" 2>/dev/null \
            | xargs grep -lE "spotless\s*\{" 2>/dev/null | grep -qv "spotless.gradle$"); then
        HAS_EXISTING_SPOTLESS=true
        log_warn "Spotless already configured in project — will skip spotless.gradle to avoid conflicts"
    else
        HAS_EXISTING_SPOTLESS=false
        log_info "Spotless: not yet configured"
    fi

    # Detect if checkstyle is already configured
    if grep -qE "apply plugin.*checkstyle|id[[:space:]]+['\"]checkstyle|checkstyle\s*\{" "${BUILD_FILE}" 2>/dev/null \
        || (find "${PROJECT_DIR}/gradle" -name "*.gradle" -o -name "*.gradle.kts" 2>/dev/null \
            | xargs grep -lE "checkstyle\s*\{" 2>/dev/null | grep -qv "checkstyle.gradle$"); then
        HAS_EXISTING_CHECKSTYLE=true
        log_warn "Checkstyle already configured in project — will overwrite checkstyle.xml rules only"
    else
        HAS_EXISTING_CHECKSTYLE=false
        log_info "Checkstyle: not yet configured"
    fi

    log_success "Project detected (${BUILD_DSL} DSL)"
}

# ─── Step 1: Create directories ──────────────────────────────────────────────
create_directories() {
    log_step "Step 1: Creating project directories"

    local dirs=(
        "${PROJECT_DIR}/gradle"
        "${PROJECT_DIR}/scripts/git-hooks"
        "${PROJECT_DIR}/config/checkstyle"
    )

    for dir in "${dirs[@]}"; do
        local rel="${dir#${PROJECT_DIR}/}"
        if [[ -d "$dir" ]]; then
            log_skip "Already exists: ${rel}/"
        elif [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would create: ${rel}/"
        else
            mkdir -p "$dir"
            log_success "Created: ${rel}/"
        fi
    done
}

# ─── Step 2: Copy Gradle files ───────────────────────────────────────────────
copy_gradle_files() {
    log_step "Step 2: Copying Gradle configuration files"

    # checkstyle.gradle — always copy (we only overwrite the XML rules if already configured)
    local dest="${PROJECT_DIR}/gradle/checkstyle.gradle"
    if [[ "${HAS_EXISTING_CHECKSTYLE}" == "true" ]]; then
        log_skip "checkstyle plugin already configured — skipping checkstyle.gradle"
    elif [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would copy → gradle/checkstyle.gradle"
    else
        cp "${SRC_GRADLE_DIR}/checkstyle.gradle" "$dest"
        log_success "gradle/checkstyle.gradle"
    fi

    # spotless.gradle — skip if project already has spotless to avoid duplicate step conflicts
    local dest_spotless="${PROJECT_DIR}/gradle/spotless.gradle"
    if [[ "${HAS_EXISTING_SPOTLESS}" == "true" ]]; then
        log_skip "Spotless already configured — skipping spotless.gradle (pre-commit hook will still call spotlessApply)"
    elif [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would copy → gradle/spotless.gradle"
    else
        write_spotless_gradle "$dest_spotless"
        log_success "gradle/spotless.gradle"
    fi

    # pre-commit.gradle
    local dest_pc="${PROJECT_DIR}/gradle/pre-commit.gradle"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would copy → gradle/pre-commit.gradle"
    else
        cp "${SRC_GRADLE_DIR}/pre-commit.gradle" "$dest_pc"
        log_success "gradle/pre-commit.gradle"
    fi
}

write_spotless_gradle() {
    local dest="$1"
    cp "${SRC_GRADLE_DIR}/spotless.gradle" "$dest"
}

# ─── Step 3: Copy Checkstyle XML config ──────────────────────────────────────
copy_checkstyle_config() {
    log_step "Step 3: Installing Checkstyle rules"

    local dest="${PROJECT_DIR}/config/checkstyle/checkstyle.xml"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would copy → config/checkstyle/checkstyle.xml"
    else
        cp "${SRC_HOOKS_DIR}/checkstyles.xml" "$dest"
        log_success "config/checkstyle/checkstyle.xml"
    fi
}

# ─── Step 4: Patch build.gradle ──────────────────────────────────────────────
patch_build_gradle() {
    log_step "Step 4: Patching ${BUILD_FILE##*/}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would add checkstyle + spotless plugins and apply from statements"
        return
    fi

    if [[ "${BUILD_DSL}" == "groovy" ]]; then
        _patch_groovy_build_file
    else
        _patch_kotlin_build_file
    fi

    # Always warn if spotless was skipped, so user knows pre-commit still calls it
    if [[ "${HAS_EXISTING_SPOTLESS}" == "true" ]]; then
        log_info "Spotless pre-commit step active via project's existing spotless config"
    fi

    log_success "${BUILD_FILE##*/} patched"
}

_patch_groovy_build_file() {
    python3 - "${BUILD_FILE}" "${SPOTLESS_VERSION}" "${HAS_EXISTING_SPOTLESS}" "${HAS_EXISTING_CHECKSTYLE}" <<'PYEOF'
import sys, re

build_file         = sys.argv[1]
spotless_ver       = sys.argv[2]
skip_spotless      = sys.argv[3] == "true"
skip_checkstyle    = sys.argv[4] == "true"

with open(build_file) as f:
    content = f.read()

original = content

# ── 1. Ensure plugins are declared ───────────────────────────────────────────
checkstyle_entry = "    id 'checkstyle'"
spotless_entry   = f"    id 'com.diffplug.spotless' version '{spotless_ver}'"

plugins_re = re.compile(r'^(plugins\s*\{)(.*?)(^\})', re.MULTILINE | re.DOTALL)
m = plugins_re.search(content)

if m:
    block_body = m.group(2)
    to_add = []
    if not skip_checkstyle and "checkstyle" not in block_body:
        to_add.append(checkstyle_entry)
    if not skip_spotless and "spotless" not in block_body:
        to_add.append(spotless_entry)
    if to_add:
        insert = "\n" + "\n".join(to_add)
        new_block = m.group(1) + m.group(2).rstrip() + insert + "\n" + m.group(3)
        content = content[:m.start()] + new_block + content[m.end():]
        print("  Added plugins to plugins {} block")
else:
    # No plugins block — fall back to apply plugin: syntax
    additions = []
    if not skip_checkstyle and "apply plugin: 'checkstyle'" not in content and 'apply plugin: "checkstyle"' not in content:
        additions.append("apply plugin: 'checkstyle'")
    if not skip_spotless and "com.diffplug.spotless" not in content:
        additions.append("apply plugin: 'com.diffplug.spotless'")
        if "buildscript" not in content:
            header = (
                f"buildscript {{\n"
                f"    repositories {{ maven {{ url 'https://plugins.gradle.org/m2/' }} }}\n"
                f"    dependencies {{ classpath 'com.diffplug.spotless:spotless-plugin-gradle:{spotless_ver}' }}\n"
                f"}}\n\n"
            )
            content = header + content
    if additions:
        content = content.rstrip() + "\n" + "\n".join(additions) + "\n"
        print("  Added apply plugin: statements (no plugins block found)")

# ── 2. Add apply from: statements (only for components we actually installed) ─
all_stmts = {
    "checkstyle": "apply from: 'gradle/checkstyle.gradle'",
    "spotless":   "apply from: 'gradle/spotless.gradle'",
    "precommit":  "apply from: 'gradle/pre-commit.gradle'",
}
active_stmts = []
if not skip_checkstyle:
    active_stmts.append(all_stmts["checkstyle"])
if not skip_spotless:
    active_stmts.append(all_stmts["spotless"])
active_stmts.append(all_stmts["precommit"])  # always add pre-commit

missing = [s for s in active_stmts if s not in content]
if missing:
    content = content.rstrip() + "\n\n// Code Quality & Git Hooks\n" + "\n".join(missing) + "\n"
    print(f"  Added {len(missing)} apply from: statement(s)")
else:
    print("  apply from: statements already present — skipped")

if content != original:
    with open(build_file, 'w') as f:
        f.write(content)
else:
    print("  No changes needed in build.gradle")
PYEOF
}

_patch_kotlin_build_file() {
    python3 - "${BUILD_FILE}" "${SPOTLESS_VERSION}" "${HAS_EXISTING_SPOTLESS}" "${HAS_EXISTING_CHECKSTYLE}" <<'PYEOF'
import sys, re

build_file      = sys.argv[1]
spotless_ver    = sys.argv[2]
skip_spotless   = sys.argv[3] == "true"
skip_checkstyle = sys.argv[4] == "true"

with open(build_file) as f:
    content = f.read()

original = content

# ── 1. Ensure plugins are declared ───────────────────────────────────────────
checkstyle_entry = '    id("checkstyle")'
spotless_entry   = f'    id("com.diffplug.spotless") version "{spotless_ver}"'

plugins_re = re.compile(r'^(plugins\s*\{)(.*?)(^\})', re.MULTILINE | re.DOTALL)
m = plugins_re.search(content)

if m:
    block_body = m.group(2)
    to_add = []
    if not skip_checkstyle and "checkstyle" not in block_body:
        to_add.append(checkstyle_entry)
    if not skip_spotless and "spotless" not in block_body:
        to_add.append(spotless_entry)
    if to_add:
        insert = "\n" + "\n".join(to_add)
        new_block = m.group(1) + m.group(2).rstrip() + insert + "\n" + m.group(3)
        content = content[:m.start()] + new_block + content[m.end():]
        print("  Added plugins to plugins {} block")
else:
    print("  WARNING: No plugins {} block found in build.gradle.kts — add plugins manually")

# ── 2. Add apply(from = ...) statements (only for installed components) ───────
all_map = {
    "checkstyle": 'apply(from = "gradle/checkstyle.gradle")',
    "spotless":   'apply(from = "gradle/spotless.gradle")',
    "precommit":  'apply(from = "gradle/pre-commit.gradle")',
}
active = []
if not skip_checkstyle:
    active.append(all_map["checkstyle"])
if not skip_spotless:
    active.append(all_map["spotless"])
active.append(all_map["precommit"])  # always

missing = [s for s in active if s not in content]
if missing:
    content = content.rstrip() + "\n\n// Code Quality & Git Hooks\n" + "\n".join(missing) + "\n"
    print(f"  Added {len(missing)} apply(from = ...) statement(s)")
else:
    print("  apply(from = ...) statements already present — skipped")

if content != original:
    with open(build_file, 'w') as f:
        f.write(content)
else:
    print("  No changes needed in build.gradle.kts")
PYEOF
}

# ─── Step 5: Copy pre-commit hook script ─────────────────────────────────────
copy_pre_commit_hook() {
    log_step "Step 5: Installing pre-commit hook script"

    local dest="${PROJECT_DIR}/scripts/git-hooks/pre-commit"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would copy → scripts/git-hooks/pre-commit (chmod +x)"
    else
        cp "${SRC_HOOKS_DIR}/pre-commit" "$dest"
        chmod +x "$dest"
        log_success "scripts/git-hooks/pre-commit (executable)"
    fi
}

# ─── Step 6: Add .gitignore entries ──────────────────────────────────────────
update_gitignore() {
    log_step "Step 6: Updating .gitignore"

    local gitignore="${PROJECT_DIR}/.gitignore"
    local entries=(
        "build/reports/checkstyle/"
        "build/reports/spotless/"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would add entries to .gitignore"
        return
    fi

    local added=0
    for entry in "${entries[@]}"; do
        if [[ -f "$gitignore" ]] && grep -qF "$entry" "$gitignore"; then
            log_skip "Already in .gitignore: ${entry}"
        else
            echo "$entry" >> "$gitignore"
            log_info "Added to .gitignore: ${entry}"
            (( added++ )) || true
        fi
    done

    [[ $added -gt 0 ]] && log_success ".gitignore updated" || log_skip ".gitignore already up to date"
}

# ─── Step 7: Gradle build ────────────────────────────────────────────────────
run_gradle_build() {
    log_step "Step 7: Running Gradle build"

    if [[ "${NO_BUILD}" == "true" ]]; then
        log_skip "Skipping build (--no-build). Run manually:"
        log_info "  cd ${PROJECT_DIR} && ./gradlew build -x test"
        return
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ./gradlew build"
        return
    fi

    log_info "Running: ./gradlew build"
    if ! (cd "${PROJECT_DIR}" && "${GRADLE_CMD}" build --console=plain); then
        log_error "Gradle build failed."
        log_info "Fix the errors above and re-run, or use --no-build to skip."
        exit 1
    fi

    log_success "Gradle build passed"

    # Verify .git/hooks/pre-commit was installed by the installGitHooks task
    if [[ -x "${PROJECT_DIR}/.git/hooks/pre-commit" ]]; then
        log_success "Pre-commit hook active in .git/hooks/"
    else
        log_warn ".git/hooks/pre-commit not found — running installGitHooks explicitly"
        (cd "${PROJECT_DIR}" && "${GRADLE_CMD}" installGitHooks --console=plain) \
            && log_success "installGitHooks completed" \
            || log_warn "installGitHooks failed — run './gradlew installGitHooks' manually"
    fi
}

# ─── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    local border="${BOLD}${GREEN}══════════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "$border"
    echo -e "${BOLD}${GREEN}  Code Quality Setup Complete!${RESET}"
    echo -e "$border"
    echo ""
    echo -e "${BOLD}Configured:${RESET}"
    if [[ "${HAS_EXISTING_CHECKSTYLE}" == "true" ]]; then
        echo -e "  ${YELLOW}~${RESET} Checkstyle ${CHECKSTYLE_VERSION}   — already configured (checkstyle.xml rules updated)"
    else
        echo -e "  ${GREEN}✓${RESET} Checkstyle ${CHECKSTYLE_VERSION}   — coding standards validation"
    fi
    if [[ "${HAS_EXISTING_SPOTLESS}" == "true" ]]; then
        echo -e "  ${YELLOW}~${RESET} Spotless               — already configured (project's config used as-is)"
    else
        echo -e "  ${GREEN}✓${RESET} Spotless ${SPOTLESS_VERSION}     — Google Java Format auto-formatting"
    fi
    echo -e "  ${GREEN}✓${RESET} Pre-commit hook    — enforced on every git commit"
    echo ""
    echo -e "${BOLD}Files written/modified:${RESET}"
    echo -e "  ${CYAN}gradle/checkstyle.gradle${RESET}          Checkstyle plugin config"
    echo -e "  ${CYAN}gradle/spotless.gradle${RESET}            Spotless plugin config"
    echo -e "  ${CYAN}gradle/pre-commit.gradle${RESET}          Git hooks Gradle task"
    echo -e "  ${CYAN}config/checkstyle/checkstyle.xml${RESET}  Checkstyle rules"
    echo -e "  ${CYAN}scripts/git-hooks/pre-commit${RESET}      Pre-commit shell script"
    echo -e "  ${CYAN}${BUILD_FILE##*/}${RESET}                        Plugins + apply from statements"
    echo ""
    echo -e "${BOLD}On every${RESET} git commit${BOLD}, the hook will:${RESET}"
    echo -e "  1. Run ${YELLOW}spotlessApply${RESET}  → auto-format Java code"
    echo -e "  2. Run ${YELLOW}checkstyleMain${RESET} → validate coding standards"
    echo -e "  3. Re-stage any files reformatted by spotless"
    echo ""
    echo -e "${GREEN}${BOLD}From the next commit, code quality is automatically enforced!${RESET}"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║   Spring Boot Code Quality Setup — SprintOak Skills  ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
    echo -e "  Project: ${PROJECT_DIR}"
    [[ "${DRY_RUN}" == "true" ]] && echo -e "  ${YELLOW}[DRY-RUN — no files will be changed]${RESET}"
    echo ""

    validate_source_files
    check_prerequisites
    detect_project
    create_directories
    copy_gradle_files
    copy_checkstyle_config
    patch_build_gradle
    copy_pre_commit_hook
    update_gitignore
    run_gradle_build

    print_summary
}

main "$@"
