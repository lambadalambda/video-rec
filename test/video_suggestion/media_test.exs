defmodule VideoSuggestion.MediaTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.Media

  test "sample_timestamps/2 uses full duration" do
    assert Media.sample_timestamps(10.0, 3) == [0.0, 5.0, 9.75]
  end

  test "extract_video_frames/2 probes duration and samples timestamps" do
    runner = fn cmd, args, _opts ->
      send(self(), {:cmd, cmd, args})

      case cmd do
        "ffprobe" ->
          {"10.0\n", 0}

        "ffmpeg" ->
          ss_idx = Enum.find_index(args, &(&1 == "-ss"))
          ts = Enum.at(args, ss_idx + 1)
          {"frame-#{ts}", 0}
      end
    end

    assert {:ok, frames} =
             Media.extract_video_frames("video.mp4",
               target_frames: 3,
               ffprobe_bin: "ffprobe",
               ffmpeg_bin: "ffmpeg",
               cmd_runner: runner
             )

    assert_receive {:cmd, "ffprobe", _}
    assert_receive {:cmd, "ffmpeg", args1}
    assert_receive {:cmd, "ffmpeg", args2}
    assert_receive {:cmd, "ffmpeg", args3}

    timestamps =
      [args1, args2, args3]
      |> Enum.map(fn args ->
        ss_idx = Enum.find_index(args, &(&1 == "-ss"))
        Enum.at(args, ss_idx + 1)
      end)

    assert timestamps == ["0.000", "5.000", "9.750"]
    assert frames == ["frame-0.000", "frame-5.000", "frame-9.750"]
  end

  test "extract_audio_to_wav/1 writes wav file via ffmpeg" do
    runner = fn cmd, args, _opts ->
      send(self(), {:cmd, cmd, args})

      wav_idx = Enum.find_index(args, &(&1 == "wav"))
      out_path = Enum.at(args, wav_idx + 1)
      File.write!(out_path, "wav-bytes")
      {"", 0}
    end

    assert {:ok, path} =
             Media.extract_audio_to_wav("video.mp4",
               ffmpeg_bin: "ffmpeg",
               cmd_runner: runner
             )

    try do
      assert_receive {:cmd, "ffmpeg", _}
      assert File.read!(path) == "wav-bytes"
    after
      File.rm_rf(path)
    end
  end
end
