' GAME-WATCH.vbs - starts scripts\game-watch.ps1 with no console window.
' Placed in the Startup folder by the GUI when you enable
' "start the FPS overlay with the game". Remove that option (or this file) to stop it.

Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
script = root & "\scripts\game-watch.ps1"

If Not fso.FileExists(script) Then
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """"
sh.Run cmd, 0, False
