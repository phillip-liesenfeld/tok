# Menu.ps1 - the right-click menu in Tok's own look (the bubble's cream, its rust outline, its font) instead of the
# stock Windows menu, and the "Start with Windows" shortcut. The menu's wiring (what each item does) is in tok.ps1.

# One style for the menu, its items, its submenu and its separators. Checked items show a ✓ in Tok's orange;
# an item with children shows ›. The palette relies on brightness, not hue: dark ink on cream,
# and the hover row is a clearly darker peach.
$script:MenuXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <SolidColorBrush x:Key="TokCream" Color="#FFFFFBF5"/>
  <SolidColorBrush x:Key="TokRust" Color="#FF8A3E28"/>
  <SolidColorBrush x:Key="TokInk" Color="#FF1E1612"/>
  <SolidColorBrush x:Key="TokHover" Color="#FFF3D9C2"/>
  <DropShadowEffect x:Key="TokShadow" BlurRadius="10" ShadowDepth="2" Direction="270" Opacity="0.35"/>

  <Style TargetType="ContextMenu">
    <Setter Property="HasDropShadow" Value="False"/>
    <Setter Property="FontFamily" Value="Segoe UI, Segoe UI Emoji, Segoe UI Symbol"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{StaticResource TokInk}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ContextMenu">
          <Border Margin="4,2,12,12" Background="{StaticResource TokCream}" BorderBrush="{StaticResource TokRust}"
                  BorderThickness="2" CornerRadius="12" Padding="4,5" Effect="{StaticResource TokShadow}">
            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle" MinWidth="150"/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="{x:Static MenuItem.SeparatorStyleKey}" TargetType="Separator">
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Separator">
          <Border Height="1.5" Margin="12,4" Background="#408A3E28"/>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="MenuItem">
    <Setter Property="Foreground" Value="{StaticResource TokInk}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="MenuItem">
          <Border x:Name="Bd" Background="Transparent" CornerRadius="8" Padding="6,5,10,5" Margin="0,1">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="22"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock x:Name="Check" Text="✓" FontSize="15" FontWeight="Bold" Foreground="#FFB4502F"
                         HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,-1,0,0" Visibility="Hidden"/>
              <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"/>
              <TextBlock x:Name="Arrow" Grid.Column="2" Text="›" FontSize="17" Margin="14,-3,0,0" Foreground="{StaticResource TokRust}"
                         VerticalAlignment="Center" Visibility="Collapsed"/>
              <Popup x:Name="PART_Popup" Placement="Right" HorizontalOffset="2" VerticalOffset="-9" AllowsTransparency="True"
                     Focusable="False" PopupAnimation="Fade"
                     IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}">
                <Border Margin="0,0,12,12" Background="{StaticResource TokCream}" BorderBrush="{StaticResource TokRust}"
                        BorderThickness="2" CornerRadius="12" Padding="4,5" Effect="{StaticResource TokShadow}">
                  <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle" MinWidth="150"/>
                </Border>
              </Popup>
            </Grid>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{StaticResource TokHover}"/></Trigger>
            <Trigger Property="IsSubmenuOpen" Value="True"><Setter TargetName="Bd" Property="Background" Value="{StaticResource TokHover}"/></Trigger>
            <Trigger Property="IsChecked" Value="True"><Setter TargetName="Check" Property="Visibility" Value="Visible"/></Trigger>
            <Trigger Property="Role" Value="SubmenuHeader"><Setter TargetName="Arrow" Property="Visibility" Value="Visible"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.6"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</ResourceDictionary>
'@

function Get-MenuResources { [Windows.Markup.XamlReader]::Parse($script:MenuXaml) }

# A menu item's header: the title, and an optional hint on a second, smaller, lighter line.
function New-MenuHeader([string]$Title, [string]$Hint = '') {
    if (-not $Hint) { return $Title }
    $sp = [Windows.Controls.StackPanel]::new()
    $null = $sp.Children.Add([Windows.Controls.TextBlock]@{ Text = $Title })
    $h = [Windows.Controls.TextBlock]@{ Text = $Hint; FontSize = 12; FontWeight = 'Normal'; Margin = [Windows.Thickness]::new(0, -1, 0, 1) }
    $h.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#FF6E5A4E')
    $null = $sp.Children.Add($h)
    $sp
}

# A small label inside a submenu ("Chatter"): a MenuItem (a menu wraps anything else in one anyway) that can't be
# clicked, hovered or reached with the keyboard, so its text lines up with the items under it.
function New-MenuLabel([string]$Text) {
    $tb = [Windows.Controls.TextBlock]@{ Text = $Text; FontSize = 12; Margin = [Windows.Thickness]::new(0, 0, 0, -4) }
    $tb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#FF8A3E28')
    [Windows.Controls.MenuItem]@{ Header = $tb; IsHitTestVisible = $false; Focusable = $false }
}

# ---------------------------------------------------------------- Start with Windows
# A shortcut to Start-Tok.vbs in the user's Startup folder (shell:startup). Nothing else is touched.
function Get-StartupShortcutPath([string]$StartupDir = [Environment]::GetFolderPath('Startup')) { Join-Path $StartupDir 'Tok.lnk' }

function Test-StartWithWindows([string]$StartupDir = [Environment]::GetFolderPath('Startup')) { Test-Path -LiteralPath (Get-StartupShortcutPath $StartupDir) }

function Set-StartWithWindows([bool]$On, [string]$Launcher, [string]$StartupDir = [Environment]::GetFolderPath('Startup')) {
    $lnk = Get-StartupShortcutPath $StartupDir
    if (-not $On) { if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }; return }
    $sh = New-Object -ComObject WScript.Shell
    try {
        $s = $sh.CreateShortcut($lnk)
        $s.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $s.Arguments = """$Launcher"""
        $s.WorkingDirectory = Split-Path $Launcher
        $s.Description = 'Tok, a small desktop creature that is Claude'
        $s.Save()
    } finally { $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
}
