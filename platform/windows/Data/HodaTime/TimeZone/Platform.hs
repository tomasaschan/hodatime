{-# LANGUAGE ForeignFunctionInterface #-}
module Data.HodaTime.TimeZone.Platform
(
   loadUTC
  ,loadLocalZone
  ,loadTimeZone
)
where

import Data.HodaTime.TimeZone.Internal
import Data.HodaTime.Instant.Internal (bigBang)
import Data.HodaTime.Offset.Internal (Offset(..))

import Control.Exception (bracket)
import System.Win32.Types (LONG)
import System.Win32.Registry
import System.Win32.Time (SYSTEMTIME(..))
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Storable (sizeOf, Storable(..))
import Foreign.Ptr (castPtr)

data REG_TZI_FORMAT = REG_TZI_FORMAT
  {
     _tziBias :: LONG
    ,_tziStandardBias :: LONG
    ,_tziDaylightBias :: LONG
    ,_tziStandardDate :: SYSTEMTIME
    ,_tziDaylightDate :: SYSTEMTIME
  }
  deriving (Show,Eq,Ord)

instance Storable REG_TZI_FORMAT where
  sizeOf _ = sizeOf (undefined :: LONG) * 3 + sizeOf (undefined :: SYSTEMTIME) * 2
  alignment _ = 4

  poke _ _ = error "poke not implemented"

  peek buf = REG_TZI_FORMAT
    <$> peekByteOff buf 0
    <*> peekByteOff buf 4
    <*> peekByteOff buf 8
    <*> peekByteOff buf 12
    <*> peekByteOff buf (12 + sizeOf (undefined :: SYSTEMTIME))

loadUTC :: IO (UtcTransitionsMap, CalDateTransitionsMap, Maybe TransitionExpressionDetails)
loadUTC = loadTimeZone "UTC"

loadLocalZone :: IO (UtcTransitionsMap, CalDateTransitionsMap, Maybe TransitionExpressionDetails, String)
loadLocalZone = do
  zone <- readLocalZoneName
  (utcM, calDateM, transExprDetails) <- loadTimeZone zone
  return (utcM, calDateM, transExprDetails, zone)

loadTimeZone :: String -> IO (UtcTransitionsMap, CalDateTransitionsMap, Maybe TransitionExpressionDetails)
loadTimeZone "UTC" = return (utcM, calDateM, transExprDet)
  where
    (utcM, calDateM, transExprDet, _) = fixedOffsetZone "UTC" (Offset 0)
loadTimeZone zone = do
  (stdAbbr, dstAbbr, tzi) <- readTziForZone zone
  return (mempty, mempty, mkExpressionDetails stdAbbr dstAbbr tzi)

-- conversion from Windows types

mkExpressionDetails :: String -> String -> REG_TZI_FORMAT -> Maybe TransitionExpressionDetails
mkExpressionDetails stdAbbr dstAbbr (REG_TZI_FORMAT bias stdBias dstBias end start) = Just $ TransitionExpressionDetails bigBang exprInfo
  where
    exprInfo = TransitionExpressionInfo startExpr endExpr stdTI dstTI
    startExpr = systemTimeToNthDayExpression start
    endExpr = systemTimeToNthDayExpression end
    stdOffSecs = 60 * (negate . fromIntegral $ bias + stdBias)
    dstOffSecs = stdOffSecs + 60 * (negate . fromIntegral $ dstBias)
    stdTI = TransitionInfo (Offset stdOffSecs) False stdAbbr
    dstTI = TransitionInfo (Offset dstOffSecs) True dstAbbr

systemTimeToNthDayExpression :: SYSTEMTIME -> TransitionExpression
systemTimeToNthDayExpression (SYSTEMTIME _ m d nth h mm s _) = NthDayExpression (fromIntegral m - 1) (adjust . fromIntegral $ nth) (fromIntegral d) s'
  where
    adjust 5 = -1
    adjust n = n - 1
    s' = h' + mm' + fromIntegral s
    h' = fromIntegral h * 60 * 60
    mm' = fromIntegral mm * 60

readLocalZoneName :: IO String
readLocalZoneName =
  bracket op regCloseKey $ \key ->
  regQueryValue key (Just "TimeZoneKeyName")
    where
      op = regOpenKeyEx hKEY_LOCAL_MACHINE hive kEY_QUERY_VALUE
      hive = "SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation"

readTziForZone :: String -> IO (String, String, REG_TZI_FORMAT)
readTziForZone zone =
  bracket op regCloseKey $ \key ->
  allocaBytes sz $ \ptr -> do
    std <- regQueryValue key (Just "Std")
    dst <- regQueryValue key (Just "Dlt")
    rvt <- regQueryValueEx key "TZI" ptr sz
    tzi <- verifyAndPeak rvt ptr
    return (std, dst, tzi)
    where
      sz = sizeOf (undefined :: REG_TZI_FORMAT)
      op = regOpenKeyEx hKEY_LOCAL_MACHINE hive kEY_QUERY_VALUE
      hive = "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Time Zones\\" ++ zone
      verifyAndPeak rvt ptr
        | rvt == rEG_BINARY = peek . castPtr $ ptr
        | otherwise         = error $ "registry corrupt: TZI variable was non-binary type: " ++ show rvt