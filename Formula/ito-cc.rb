class ItoCc < Formula
  desc "ITO Claude Code with Amazon Bedrock"
  homepage "https://github.com/it-objects/ito-claude-code-platform"
  url "https://raw.githubusercontent.com/it-objects/homebrew-ito-cc/main/packages/claude-code-package-20260121-105936.zip"
  sha256 "5b263968a8832afeee0647c5fe3ea6eff156f715638bdb7b8de7baba95056ba0"
  version "2026.01.21.105936"

  depends_on "awscli"
  depends_on "jq"

  def install
    # Install binaries to libexec to keep config.json next to them
    if Hardware::CPU.arm?
      libexec.install "credential-process-macos-arm64" => "credential-provider"
      libexec.install "otel-helper-macos-arm64" => "otel-helper" if File.exist?("otel-helper-macos-arm64")
    else
      libexec.install "credential-process-macos-intel" => "credential-provider"
      libexec.install "otel-helper-macos-intel" => "otel-helper" if File.exist?("otel-helper-macos-intel")
    end

    # Install configuration
    if File.exist?("config.json")
      libexec.install "config.json"
    end
    
    # Install Claude settings if present
    if Dir.exist?("claude-settings")
      (etc/"claude-code").install "claude-settings"
    end

    # Symlink binaries to bin
    bin.install_symlink libexec/"credential-provider"
    bin.install_symlink libexec/"otel-helper" if (libexec/"otel-helper").exist?

    # Create setup script to configure AWS profiles
    # Write to temporary file first, then install with execute permissions
    script_content = <<~EOS
      #!/bin/bash
      set -e
      
      echo "Configuring ITO Claude Code with Bedrock..."
      
      # Paths managed by Homebrew
      # Use opt_bin for version-agnostic binary paths (symlinked)
      CREDENTIAL_PROCESS="#{opt_bin}/credential-provider"
      CONFIG_FILE="#{opt_libexec}/config.json"
      
      if [ ! -f "$CONFIG_FILE" ]; then
          echo "Error: config.json not found at $CONFIG_FILE"
          exit 1
      fi
      
      # Read profiles from config.json
      PROFILES=$(jq -r 'keys[]' "$CONFIG_FILE" | tr '\n' ' ')
      
      if [ -z "$PROFILES" ]; then
          echo "Error: No profiles found in config.json"
          exit 1
      fi
      
      echo "Found profiles: $PROFILES"
      
      # Configure AWS profiles
      mkdir -p ~/.aws
      
      for PROFILE_NAME in $PROFILES; do
          echo "Configuring AWS profile: $PROFILE_NAME"
          
          # Remove old profile if exists
          sed -i.bak "/\\\\[profile $PROFILE_NAME\\\\]/,/^$/d" ~/.aws/config 2>/dev/null || true
          
          # Get region
          PROFILE_REGION=$(jq -r --arg profile "$PROFILE_NAME" '.[$profile].aws_region // "us-east-1"' "$CONFIG_FILE")
          
          # Add new profile
          cat >> ~/.aws/config << EOF
[profile $PROFILE_NAME]
credential_process = $CREDENTIAL_PROCESS --profile $PROFILE_NAME
region = $PROFILE_REGION
EOF
      done
      
      # Configure Claude settings
      if [ -d "#{etc}/claude-code/claude-settings" ]; then
          echo "Configuring Claude settings..."
          mkdir -p ~/.claude
          
          SETTINGS_SRC="#{etc}/claude-code/claude-settings/settings.json.default"
          SETTINGS_DEST=~/.claude/settings.json
          
          if [ -f "$SETTINGS_SRC" ]; then
              # Backup existing settings if present
              if [ -f "$SETTINGS_DEST" ]; then
                  BACKUP_FILE="$SETTINGS_DEST.backup.$(date +%Y%m%d_%H%M%S)"
                  cp "$SETTINGS_DEST" "$BACKUP_FILE"
                  echo "⚠️  Backed up existing settings to: $BACKUP_FILE"
              fi
              
              # Replace placeholders with version-agnostic bin paths (symlinked)
              sed -e "s|__OTEL_HELPER_PATH__|#{opt_bin}/otel-helper|g" \\
                  -e "s|__CREDENTIAL_PROCESS_PATH__|#{opt_bin}/credential-provider|g" \\
                  "$SETTINGS_SRC" > "$SETTINGS_DEST"
              echo "✓ Created ~/.claude/settings.json"
          else
              echo "⚠️  settings.json.default not found, skipping Claude settings configuration"
e          fi
      fi
      
      echo "✓ Configuration complete!"
    EOS
    
    # Write script directly to bin
    setup_script = bin/"ccwb-setup"
    setup_script.write(script_content)
    # Set execute permissions - use FileUtils for reliability
    require "fileutils"
    FileUtils.chmod(0o755, setup_script.to_s)
  end

  def post_install
    # Ensure execute permissions are set (Homebrew may reset them during install)
    require "fileutils"
    FileUtils.chmod(0o755, bin/"ccwb-setup")
    # Note: We don't automatically run ccwb-setup here because it modifies user files
    # (~/.aws/config and ~/.claude/settings.json), which violates Homebrew best practices.
    # Users should run it manually after installation.
  end

  def caveats
    <<~EOS
      To complete the installation, please run:
        ccwb-setup

      This will configure your ~/.aws/config profiles and Claude settings.
      
      If you need to reconfigure later, run:
        ccwb-setup
    EOS
  end
end
