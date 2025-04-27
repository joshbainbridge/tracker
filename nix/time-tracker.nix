{ config, lib, pkgs, ... }:

let
  cfg = config.services.time-tracker;
  
  capture-screenshot = pkgs.writeShellApplication {
    name = "capture-screenshot";
    runtimeInputs = with pkgs; [ ];
    text = builtins.readFile ../bin/capture-screenshot.sh;
  };

  process-screenshots = pkgs.writeShellApplication {
    name = "process-screenshots";
    runtimeInputs = with pkgs; [ jq ollama ];
    text = builtins.readFile ../bin/process-screenshots.sh;
  };
in {
  options.services.time-tracker = {
    enable = lib.mkEnableOption "Time tracker service";
    
    screenshotInterval = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Interval in seconds between screenshots";
    };
    
    processingInterval = lib.mkOption {
      type = lib.types.int;
      default = 1800;
      description = "Interval in seconds between processing screenshots";
    };
  };
  
  config = lib.mkIf cfg.enable {
    home.packages = [ capture-screenshot process-screenshots ];
    
    # Ensure ollama is enabled
    services.ollama.enable = true;
    
    # macOS-specific configuration with LaunchAgents
    launchd.agents = {
      time-tracker-capture = {
        enable = true;
        config = {
          Label = "org.nix-community.home.time-tracker-capture";
          ProgramArguments = [ "${capture-screenshot}/bin/capture-screenshot" ];
          KeepAlive = false;
          RunAtLoad = true;
          StartInterval = cfg.screenshotInterval;
        };
      };
      
      time-tracker-process = {
        enable = true;
        config = {
          Label = "org.nix-community.home.time-tracker-process";
          ProgramArguments = [ "${process-screenshots}/bin/process-screenshots" ];
          KeepAlive = false;
          RunAtLoad = true;
          StartInterval = cfg.processingInterval;
        };
      };
    };
  };
}
