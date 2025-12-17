class ItoCc < Formula
  desc "ITO Claude Code with Amazon Bedrock"
  homepage "https://github.com/it-objects/ito-claude-code-platform"
  url "https://raw.githubusercontent.com/it-objects/homebrew-ito-cc/main/packages/claude-code-package-20251217-163431.zip"
  sha256 "d5a25c7ca8dab9a21c98fb49a7b62c76a4a77dc556c544544c454ad948272119"
  version "2025.12.17.163431"

  depends_on "awscli"
  depends_on "python@3.12"

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
      CREDENTIAL_PROCESS="#{libexec}/credential-provider"
      CONFIG_FILE="#{libexec}/config.json"
      
      if [ ! -f "$CONFIG_FILE" ]; then
          echo "Error: config.json not found at $CONFIG_FILE"
          exit 1
      fi
      
      # Read profiles from config.json
      PROFILES=$(python3 -c "import json; profiles = list(json.load(open('$CONFIG_FILE')).keys()); print(' '.join(profiles))")
      
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
          PROFILE_REGION=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('$PROFILE_NAME', {}).get('aws_region', 'us-east-1'))")
          
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
          
          SETTINGS_SRC="#{etc}/claude-code/claude-settings/settings.json"
          if [ -f "$SETTINGS_SRC" ]; then
              # Replace placeholders
              sed -e "s|__OTEL_HELPER_PATH__|#{libexec}/otel-helper|g" \\
                  -e "s|__CREDENTIAL_PROCESS_PATH__|#{libexec}/credential-provider|g" \\
                  "$SETTINGS_SRC" > ~/.claude/settings.json
              echo "Updated ~/.claude/settings.json"
          fi
      fi
      
      echo "✓ Configuration complete!"
    EOS
    
    # Write to temporary file and set execute permissions before installing
    temp_script = buildpath/"ccwb-setup"
    temp_script.write(script_content)
    temp_script.chmod(0755)
    bin.install temp_script
  end

  def post_install
    # Automatically run setup script after installation
    # Use opt_bin for version-agnostic path (points to /opt/homebrew/opt/ito-cc/bin)
    system opt_bin/"ccwb-setup"
  end

  def caveats
    <<~EOS
      Configuration has been automatically applied to your ~/.aws/config profiles and Claude settings.
      
      If you need to reconfigure, run:
        ccwb-setup
    EOS
  end
end
