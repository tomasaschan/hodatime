module Data.HodaTime.Calendar.Iso
(
  fromWeekDate
)
where

import Data.HodaTime.Calendar.Gregorian.Internal hiding (fromWeekDate)
import qualified Data.HodaTime.Calendar.Gregorian.Internal as GI
import Data.HodaTime.CalendarDateTime.Internal (CalendarDate(..), Year, WeekNumber)

-- | Smart constuctor for ISO calendar date based day within year week.  Note that this method assumes weeks start on Monday and the first week of the year is the one
--   which has at least four days in the new year.  See the Gregorian module for alternative behavior
fromWeekDate :: WeekNumber -> DayOfWeek Gregorian -> Year -> Maybe (CalendarDate Gregorian)
fromWeekDate = GI.fromWeekDate 4 Monday