defmodule VideoSuggestion.Media do
  @moduledoc false

  @default_target_frames 10
  @end_offset_seconds 0.25

  def extract_video_frames(video_path, opts \\ []) when is_binary(video_path) do
    cmd_runner = Keyword.get(opts, :cmd_runner, &System.cmd/3)
    ffprobe = Keyword.get(opts, :ffprobe_bin, ffprobe_bin())
    ffmpeg = Keyword.get(opts, :ffmpeg_bin, ffmpeg_bin!())
    target_frames = Keyword.get(opts, :target_frames, @default_target_frames)

    duration_seconds = probe_duration_seconds(video_path, ffprobe, cmd_runner)
    timestamps = sample_timestamps(duration_seconds, target_frames)

    frames =
      timestamps
      |> Enum.reduce([], fn timestamp, acc ->
        case extract_frame_png(video_path, timestamp, ffmpeg, cmd_runner) do
          {:ok, png} -> [png | acc]
          {:error, _} -> acc
        end
      end)
      |> Enum.reverse()

    if frames == [] do
      {:error, :no_frames}
    else
      {:ok, frames}
    end
  end

  def extract_audio_to_wav(video_path, opts \\ []) when is_binary(video_path) do
    cmd_runner = Keyword.get(opts, :cmd_runner, &System.cmd/3)
    ffmpeg = Keyword.get(opts, :ffmpeg_bin, ffmpeg_bin!())

    tmp_dir = System.tmp_dir!()
    filename = "video_suggestion_audio_#{System.unique_integer([:positive])}.wav"
    out_path = Path.join(tmp_dir, filename)

    args = [
      "-y",
      "-i",
      video_path,
      "-vn",
      "-ac",
      "1",
      "-ar",
      "16000",
      "-f",
      "wav",
      out_path,
      "-loglevel",
      "error"
    ]

    {_out, status} = cmd_runner.(ffmpeg, args, stderr_to_stdout: true)

    if status == 0 and File.exists?(out_path) do
      {:ok, out_path}
    else
      File.rm_rf(out_path)
      {:error, :ffmpeg_failed}
    end
  end

  def sample_timestamps(duration_seconds, target_frames \\ @default_target_frames)

  def sample_timestamps(_duration_seconds, target_frames) when not is_integer(target_frames) do
    []
  end

  def sample_timestamps(_duration_seconds, target_frames) when target_frames <= 0 do
    []
  end

  def sample_timestamps(duration_seconds, 1)
      when is_number(duration_seconds) and duration_seconds > 0 do
    [0.0]
  end

  def sample_timestamps(nil, target_frames) do
    for i <- 0..(target_frames - 1), do: i * 1.0
  end

  def sample_timestamps(duration_seconds, target_frames)
      when is_number(duration_seconds) and duration_seconds > 0 and target_frames > 1 do
    step = duration_seconds / (target_frames - 1)
    max_ts = max(duration_seconds - @end_offset_seconds, 0.0)

    for i <- 0..(target_frames - 1) do
      ts = i * step
      if i == target_frames - 1, do: min(ts, max_ts), else: min(ts, max_ts)
    end
  end

  defp extract_frame_png(video_path, timestamp, ffmpeg, cmd_runner)
       when is_number(timestamp) and is_binary(ffmpeg) do
    ts = :erlang.float_to_binary(timestamp * 1.0, decimals: 3)

    args = [
      "-hide_banner",
      "-loglevel",
      "error",
      "-ss",
      ts,
      "-i",
      video_path,
      "-an",
      "-sn",
      "-dn",
      "-frames:v",
      "1",
      "-f",
      "image2pipe",
      "-vcodec",
      "png",
      "pipe:1"
    ]

    {out, status} = cmd_runner.(ffmpeg, args, stderr_to_stdout: true)

    if status == 0 and is_binary(out) and byte_size(out) > 0 do
      {:ok, out}
    else
      {:error, :ffmpeg_failed}
    end
  end

  defp probe_duration_seconds(video_path, nil, _cmd_runner) do
    _ = video_path
    nil
  end

  defp probe_duration_seconds(video_path, ffprobe, cmd_runner) do
    args = [
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      video_path
    ]

    case cmd_runner.(ffprobe, args, stderr_to_stdout: true) do
      {out, 0} ->
        out
        |> to_string()
        |> String.trim()
        |> Float.parse()
        |> case do
          {value, _} when value > 0 -> value
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp ffmpeg_bin! do
    System.get_env("FFMPEG_BIN") || System.find_executable("ffmpeg") ||
      raise "ffmpeg not found"
  end

  defp ffprobe_bin do
    System.get_env("FFPROBE_BIN") || System.find_executable("ffprobe")
  end
end
