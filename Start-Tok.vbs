' Starts Tok with no console window. Double-click, or put a shortcut to this
' file in shell:startup to have it appear at login.
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "pwsh -STA -NoProfile -WindowStyle Hidden -File """ & here & "\tok.ps1""", 0, False
