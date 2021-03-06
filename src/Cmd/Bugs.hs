module Cmd.Bugs (bugsCmd) where

import Bugzilla
import Package

bugsCmd :: Maybe String -> IO ()
bugsCmd mpkg = do
  pkg <- getPackageName mpkg
  (bugs, _) <- bugsSession $ pkgBugs pkg .&&. statusOpen
  mapM_ putBug $ sortBugsByProduct bugs
