defmodule EverydayDash.Dashboard.HabitifyHistoryTest do
  use ExUnit.Case, async: true

  alias EverydayDash.Dashboard.HabitifyHistory

  test "builds a binary series and counts completed days across sparse log history" do
    logged_values_by_date = %{
      ~D[2026-03-05] => 1.0,
      ~D[2026-03-07] => 0.5,
      ~D[2026-03-08] => 0.0,
      ~D[2026-03-09] => 0.25
    }

    result = HabitifyHistory.build(logged_values_by_date, 1.0, 5, ~D[2026-03-09])

    assert result.series == [1, 0, 0, 0, 0]
    assert result.completed_days == 1
    assert result.total_days == 5
    assert result.today_status == "in_progress"
  end

  test "marks completed when logged value meets the goal threshold" do
    logged_values_by_date = %{
      ~D[2026-03-07] => 2.0,
      ~D[2026-03-08] => 1.0,
      ~D[2026-03-09] => 2.0
    }

    result = HabitifyHistory.build(logged_values_by_date, 2.0, 3, ~D[2026-03-09])

    assert result.series == [1, 0, 1]
    assert result.completed_days == 2
    assert result.today_status == "completed"
  end
end
