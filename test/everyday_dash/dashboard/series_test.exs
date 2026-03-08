defmodule EverydayDash.Dashboard.SeriesTest do
  use ExUnit.Case, async: true

  alias EverydayDash.Dashboard.Series

  test "builds raw values and trailing averages across the requested window" do
    counts = %{
      ~D[2026-03-01] => 1,
      ~D[2026-03-02] => 2,
      ~D[2026-03-03] => 3,
      ~D[2026-03-04] => 4,
      ~D[2026-03-05] => 5,
      ~D[2026-03-06] => 6,
      ~D[2026-03-07] => 7
    }

    result = Series.build(counts, 3, 7, ~D[2026-03-07])

    assert Enum.map(result.raw, & &1.value) == [5, 6, 7]

    averages = Enum.map(result.average, &Float.round(&1.value, 2))

    assert averages == [2.14, 3.0, 4.0]
  end
end
