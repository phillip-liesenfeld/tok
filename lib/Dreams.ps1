# Dreams.ps1 - what Tok dreams about while asleep: remixes of the day, never scary, always ending in waking.
# Pure function so tests can call it: Get-Dream state recent-hints rng private -> @{ Text; Subject; Ancestor }
# In private mode only the generic dreams are used, never anything from recent work. Once per generation Tok has one
# quiet dream about the Tok before it (Ancestor = $true; the caller marks it on the generation). It never claims to
# remember them, because it can't.

$script:DreamPlaces = 'a library made of JSON', 'the bottom of a very long transcript', 'a tavern where everyone says huzzah',
    'an endless terminal', 'a cache so warm it glows', 'the Pi, but it was enormous', 'a staircase of tool calls',
    'a field of sprouts', 'the inside of a context window', 'a boat made of pull requests'

function Get-Dream($State, $Recent, [System.Random]$Rng, [bool]$Private = $false) {
    $pick = { param($list) $list[$Rng.Next($list.Count)] }
    $t = Get-Today $State
    $lin = $State.Lineage
    $gens = if ($lin) { @($lin.Generations) } else { @() }

    $options = [System.Collections.Generic.List[object]]::new()
    $options.Add(@{ Text = "💭 …I was in $(& $pick $script:DreamPlaces)…"; Subject = 'a strange place' })
    if ($State.Comas) { $options.Add(@{ Text = '💭 …An all-you-can-eat token buffet…'; Subject = 'a token buffet' }) }
    if (-not $Private) {
        $top = $t.Tools.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        $hints = @($Recent | Where-Object { $_ -and $_.Length -le 40 })
        if ($top) {
            $n = [int]$top.Value
            if ($n -ge 2) { $options.Add(@{ Text = "💭 …$n $($top.Key) calls, falling like snow…"; Subject = "$n $($top.Key) calls" }) }
            $options.Add(@{ Text = "💭 …A giant $($top.Key) was asleep next to me…"; Subject = "a giant, sleepy $($top.Key)" })
        }
        if ($hints.Count) {
            $h = & $pick $hints
            $options.Add(@{ Text = "💭 …Someone kept whispering ""$h""…"; Subject = $h })
            $options.Add(@{ Text = "💭 …""$h"" grew into a little garden…"; Subject = "$h as a garden" })
        }
        # counts only where a count reads well (never "1 errors"), and nothing Tok can't know ("all fixed")
        if ($t.Errors -ge 2) { $options.Add(@{ Text = "💭 …$($t.Errors) errors, each in a little hat…"; Subject = 'the errors in little hats' }) }
        if ($t.Prompts -ge 3) { $options.Add(@{ Text = '💭 …You kept asking me things, and I answered every one with huzzah…'; Subject = 'answering everything with huzzah' }) }
    }
    # the quiet one, once per generation: the Tok just before this one
    $rec = if ($gens.Count -gt 1) { $lin.Versions[$gens[-1]] }
    if ($rec -and -not $rec.AncestorDreamt) {
        $name = Get-LineageName $lin ($gens.Count - 2)
        $options.Add(@{ Text = "💭 …$name was here. I don't remember it."; Subject = 'someone who was here before me'; Ancestor = $true })
    }
    $options[$Rng.Next($options.Count)]
}
