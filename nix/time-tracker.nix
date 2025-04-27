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
      default = 5;
      description = "Interval in minutes between screenshots";
    };

    processingInterval = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Interval in minutes between processing screenshots";
    };

    workHoursOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to run only during configured work hours";
    };

    weekdaysOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to run only on weekdays (Monday-Friday)";
    };

    workStartHour = lib.mkOption {
      type = lib.types.int;
      default = 9;
      description = "Start hour of work day (24-hour format, 0-23)";
    };

    workEndHour = lib.mkOption {
      type = lib.types.int;
      default = 18;
      description = "End hour of work day (24-hour format, 0-23)";
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
          RunAtLoad = false;
          StartCalendarInterval = let
            weekdays = if cfg.weekdaysOnly
                       then [ 1 2 3 4 5 ]
                       else [ 0 1 2 3 4 5 6 ];
            hours = if cfg.workHoursOnly
                    then lib.lists.range cfg.workStartHour cfg.workEndHour
                    else lib.lists.range 0 23;
            max = 60;
            step = cfg.screenshotInterval;
            count = builtins.div (max - 1) step;
            minutes = builtins.genList (i: i * step) count;
          in lib.concatLists (map (minute:
              lib.concatLists (map (hour:
                map (weekday: {
                  Weekday = weekday;
                  Hour = hour;
                  Minute = minute;
                }) weekdays
              ) hours)
            ) minutes);
        };
      };

      time-tracker-process = {
        enable = true;
        config = {
          Label = "org.nix-community.home.time-tracker-process";
          ProgramArguments = [ "${process-screenshots}/bin/process-screenshots" ];
          KeepAlive = false;
          RunAtLoad = false;
          StartInterval = cfg.processingInterval * 60;
        };
      };
    };
  };
}
