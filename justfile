# Serve the documentation site
docs-serve:
    cd docs && bundle exec jekyll s

# Install dependencies for the documentation site
docs-install:
    cd docs && bundle install

# Generate usage documentation
docs-generate-usage:
    ./bin/noir --help-all | sed 's/\[[0-9;]*m//g' > docs/_includes/usage.md

# Format the code using crystal tool format
lint-format:
    crystal tool format

# Lint the code using ameba
lint-ameba:
    ameba --fix

# Run all linting tasks
lint-all: lint-format lint-ameba

# Check for missing flags in completion scripts
completion-check:
    @noir_help_output=$(./bin/noir -h)
    @noir_flags=$(echo "$noir_help_output" | grep -oE '^\s+(-\w|--\w[\w-]*)' | sort -u)
    @zsh_completion=$(./bin/noir --generate-completion=zsh)
    @bash_completion=$(./bin/noir --generate-completion=bash)
    @fish_completion=$(./bin/noir --generate-completion=fish)

    @missing_flags_zsh=$(comm -23 <(echo "$noir_flags") <(echo "$zsh_completion" | grep -oE '(-\w|--\w[\w-]*)' | sort -u))
    @if [ -z "$missing_flags_zsh" ]; then \
        echo "All flags are present in the zsh completion script."; \
    else \
        echo "Missing flags in zsh completion script:"; \
        echo "$missing_flags_zsh"; \
    fi

    @missing_flags_bash=$(comm -23 <(echo "$noir_flags") <(echo "$bash_completion" | grep -oE '(-\w|--\w[\w-]*)' | sort -u))
    @if [ -z "$missing_flags_bash" ]; then \
        echo "All flags are present in the bash completion script."; \
    else \
        echo "Missing flags in bash completion script:"; \
        echo "$missing_flags_bash"; \
    fi

    @missing_flags_fish=$(comm -23 <(echo "$noir_flags") <(echo "$fish_completion" | grep -oE '(-\w|--\w[\w-]*)' | sort -u))
    @if [ -z "$missing_flags_fish" ]; then \
        echo "All flags are present in the fish completion script."; \
    else \
        echo "Missing flags in fish completion script:"; \
        echo "$missing_flags_fish"; \
    fi
