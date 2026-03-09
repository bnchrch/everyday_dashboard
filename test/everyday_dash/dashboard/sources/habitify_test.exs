defmodule EverydayDash.Dashboard.Sources.HabitifyTest do
  use ExUnit.Case, async: true

  alias EverydayDash.Dashboard.Sources.Habitify

  test "formats the logs range start with an explicit utc offset for Habitify" do
    assert Habitify.format_target_date(~D[2026-03-09]) =~
             ~r/^2026-03-09T00:00:00[+-]\d{2}:\d{2}$/
  end
end
