module Koji (
  kojiNVRTags,
  kojiBuildStatus,
  kojiBuildTags,
  kojiGetBuildID,
  kojiLatestNVR,
  kojiScratchUrl,
  buildIDInfo,
  BuildState(..),
  kojiBuild,
  kojiBuildBranch
  ) where

import Data.Char (isDigit)

import Fedora.Koji
import SimpleCmd

import Common
import Krb

kojiNVRTags :: String -> IO (Maybe [String])
kojiNVRTags nvr = do
  mbldid <- kojiGetBuildID nvr
  case mbldid of
    Nothing -> return Nothing
    Just bldid -> Just <$> kojiBuildTags (buildIDInfo bldid)

kojiBuildStatus :: String -> IO (Maybe BuildState)
kojiBuildStatus nvr =
  kojiGetBuildState (BuildInfoNVR nvr)

kojiLatestNVR :: String -> String -> IO (Maybe String)
kojiLatestNVR tag pkg = do
  mbld <- kojiLatestBuild tag pkg
  return $ case mbld of
             Nothing -> Nothing
             Just bld -> lookupStruct "nvr" bld

kojiScratchUrl :: Bool -> String -> IO (Maybe String)
kojiScratchUrl noscratch srpm =
    if noscratch
    then return Nothing
    else Just <$> kojiScratchBuild "rawhide" srpm

kojiScratchBuild :: String -> FilePath -> IO String
kojiScratchBuild target srpm =
  kojiBuild target ["--scratch", "--no-rebuild-srpm", srpm]

kojiBuild :: String -> [String] -> IO String
kojiBuild target args = do
  krbTicket
  cmd_ "date" []
  -- FIXME setTermTitle nvr
  out <- cmd "koji" $ ["build", "--nowait", target] ++ args
  putStrLn out
  let kojiurl = last $ words out
      task = read $ takeWhileEnd isDigit kojiurl
  okay <- kojiWatchTask task
  if not okay
    then error' "scratch build failed"
    else return kojiurl
  where
    kojiWatchTask :: Int -> IO Bool
    kojiWatchTask task = do
      res <- cmdBool "koji" ["watch-task", show task]
      if res then return True
        else do
        mst <- kojiGetTaskState (TaskId task)
        case mst of
          Just TaskClosed -> return True
          Just TaskFailed -> error "Task failed!"
          _ -> kojiWatchTask task

    takeWhileEnd :: (a -> Bool) -> [a] -> [a]
    takeWhileEnd p = reverse . takeWhile p . reverse

kojiBuildBranch :: String -> [String] -> IO ()
kojiBuildBranch target args = do
  giturl <- cmd "fedpkg" ["giturl"]
  -- FIXME --target
  void $ kojiBuild target $ args ++ ["--fail-fast", giturl]
