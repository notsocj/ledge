using System.IO;

namespace Ledge;

/// <summary>Files you dropped on the island to keep handy, until you drag them out somewhere.
/// It holds paths, not copies: nothing is moved or duplicated.</summary>
public sealed class Shelf
{
    readonly List<string> files = [];

    public IReadOnlyList<string> Files => files;
    public event Action? Changed;

    public int Add(IEnumerable<string> paths)
    {
        var added = 0;
        foreach (var path in paths)
        {
            if (files.Contains(path, StringComparer.OrdinalIgnoreCase)) continue;
            files.Add(path);
            added++;
        }
        if (added > 0) Changed?.Invoke();
        return added;
    }

    public void Remove(string path)
    {
        if (files.Remove(path)) Changed?.Invoke();
    }

    public void Clear()
    {
        files.Clear();
        Changed?.Invoke();
    }

    /// <summary>Forgets files that were moved or deleted since they were dropped.</summary>
    public void Prune()
    {
        if (files.RemoveAll(path => !File.Exists(path) && !Directory.Exists(path)) > 0) Changed?.Invoke();
    }
}
