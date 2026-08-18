vim9script

if exists('s:is_loaded')
  finish
endif
var is_loaded: bool = true

import autoload 'tartree/tartreeRW.vim' as RW
import autoload 'tartree/archiveBackend.vim' as AB
import autoload 'tartree/archiveRegistry.vim' as Registry
import autoload 'tartree/tarBackend.vim' as TB

# ----------------------------------------------------------------------------
# TarNode: a single entry (file or directory) in the archive tree.
# ----------------------------------------------------------------------------
class TarNode
  public var name: string = ''
  public var fullPath: string = ''
  public var isDir: bool = false
  public var expanded: bool = false
  public var children: list<TarNode> = []
  public var level: number = 0

  def new(this.name, this.fullPath, this.isDir, this.level)
  enddef
endclass

const HeaderNode: TarNode = TarNode.new('', '', false, -1)

# ----------------------------------------------------------------------------
# Module-level helpers (no instance state required)
# ----------------------------------------------------------------------------

def IsHiddenPath(normPath: string): bool
  if get(g:, 'tartree_show_hidden', 0)
    return false
  endif
  for part in split(normPath, '/')
    if part =~ '^\.'
      return true
    endif
  endfor
  return false
enddef

##############################################################################
# TarTreeWindow: owns the sidebar buffer/window and the tree state for one
# archive.
##############################################################################
class TarTreeWindow
  var bufnr: number = -1
  var winid: number = -1
  var archivePath: string = ''
  var rootPath: string = ''
  var treeNodes: list<TarNode> = []
  var lineNodeMap: list<TarNode> = []
  var showHelp: bool = false

  var backend: AB.ArchiveBackend = TB.GnuTar.new()

  # -- Public actions --------------------------------------------------

  def Open(argPath: string = ''): void
    var archive: string = argPath
    if empty(archive)
      archive = expand('%:p')
    endif

    if empty(archive) || !filereadable(archive)
      archive = input('Path to archive: ', '', 'file')
      if empty(archive) || !filereadable(archive)
        echoerr '[TarTree] Invalid or unreadable archive file: ' .. archive
        return
      endif
    endif

    this.archivePath = fnamemodify(archive, ':p')

    var archiveType = AB.ArchiveTypeDetect(this.archivePath)
    if archiveType ==# 'unknown'
      echoerr '[TarTree] Could not determine archive type for: ' .. this.archivePath
      return
    endif
    try
      this.backend = Registry.NewBackend(archiveType)
    catch
      echoerr $'[TarTree] No backend available for archive type "{archiveType}": {this.archivePath}'
      return
    endtry

    var lines: list<string> = this.backend.List(this.archivePath)
    if v:shell_error != 0 || empty(lines)
      echoerr '[TarTree] Failed to execute archive-listing command or empty archive.'
      return
    endif

    this.BuildTreeData(lines)
    this.CreateTreeWindow()
    this.RenderTree()
  enddef

  def AutoOpen(path: string): void
    if filereadable(path)
      this.Open(path)
    endif
  enddef

  def Toggle(): void
    if bufexists(this.bufnr) && bufwinnr(this.bufnr) != -1
      this.Close()
    elseif !empty(this.archivePath) && filereadable(this.archivePath)
      this.Open(this.archivePath)
    else
      this.Open('')
    endif
  enddef

  def Close(): void
    var win: number = bufwinnr(this.bufnr)
    if win != -1
      execute ':' .. win .. 'wincmd q'
    endif
  enddef

  def ActionOpen(): void
    var node: TarNode = this.GetCurrentNode()
    if node.level == -1
      return
    endif

    if node.isDir
      var cur = getcurpos()
      node.expanded = !node.expanded
      this.RenderTree()
      call setpos('.', cur) 
    else
      wincmd w
      call RW.CreateWindow(this.archivePath, node.fullPath, this.backend)
    endif
  enddef

  def ActionRefresh(): void
    this.Open(this.archivePath)
  enddef

  def ToggleHelp(): void
    this.showHelp = !this.showHelp
    this.RenderTree()
  enddef

  # -- Tree construction -------------------------------------------------

  def BuildTreeData(rawLines: list<string>): void
    var rootName: string = fnamemodify(this.archivePath, ':t')
    this.rootPath = ''

    var nodeMap: dict<TarNode> = {}
    var rootNode: TarNode = TarNode.new(rootName, '', true, 0)
    rootNode.expanded = true
    nodeMap[''] = rootNode

    for line in rawLines
      var cleanLine: string = substitute(line, '^./', '', '')
      if empty(cleanLine) || cleanLine == '.'
        continue
      endif

      var isDirEntry: bool = (cleanLine =~ '/$')
      var normPath: string = substitute(cleanLine, '/\+$', '', '')

      if IsHiddenPath(normPath)
        continue
      endif

      var parts: list<string> = split(normPath, '/')
      var curr: string = ''

      for i in range(len(parts))
        var part: string = parts[i]
        var parent: string = curr
        curr = empty(curr) ? part : curr .. '/' .. part
        var isLast: bool = (i == len(parts) - 1)
        var nodeIsDir: bool = !isLast || isDirEntry

        if !has_key(nodeMap, curr)
          var newNode: TarNode = TarNode.new(part, curr .. (nodeIsDir ? '/' : ''), nodeIsDir, i + 1)
          nodeMap[curr] = newNode
          if has_key(nodeMap, parent)
            add(nodeMap[parent].children, newNode)
          endif
        endif
      endfor
    endfor

    this.SortChildren(rootNode)
    this.treeNodes = [rootNode]
  enddef

  def SortChildren(node: TarNode): void
    if empty(node.children)
      return
    endif

    sort(node.children, (a, b) => {
      if a.isDir && !b.isDir
        return -1
      elseif !a.isDir && b.isDir
        return 1
      endif
      return a.name ==? b.name ? 0 : (a.name >? b.name ? 1 : -1)
    })

    for child in node.children
      if child.isDir
        this.SortChildren(child)
      endif
    endfor
  enddef

  # -- Window / rendering -------------------------------------------------

  def CreateTreeWindow(): void
    if bufexists(this.bufnr) && bufwinnr(this.bufnr) != -1
      execute ':' .. bufwinnr(this.bufnr) .. 'wincmd w'
      return
    endif

    var winWidth = g:tartree_win_width
    execute 'topleft :' .. winWidth .. 'vnew'

    this.bufnr = bufnr('%')
    this.winid = win_getid()

    setlocal buftype=nofile
    setlocal bufhidden=wipe
    setlocal noswapfile
    setlocal nowrap
    setlocal cursorline
    setlocal nonumber
    setlocal norelativenumber
    setlocal filetype=tartree

    this.ApplyMappings()
    this.ApplyColorScheme()
  enddef

  def ApplyColorScheme(): void
    highlight link TarTreeDir Directory
    syntax match TarTreeDir /\s\([^\/]*\)\//
  enddef

  def ApplyMappings(): void
    var opts = '<buffer> <silent> <nowait> '

    execute 'nnoremap ' .. opts .. 'o :call tartree#ActionOpen()<CR>'
    execute 'nnoremap ' .. opts .. '<CR> :call tartree#ActionOpen()<CR>'
    execute 'nnoremap ' .. opts .. 'r :call tartree#ActionRefresh()<CR>'
    execute 'nnoremap ' .. opts .. '? :call tartree#ToggleHelp()<CR>'
    execute 'nnoremap ' .. opts .. 'q :call tartree#Close()<CR>'
  enddef

  def RenderTree(): void
    setlocal modifiable
    silent :%delete _

    this.lineNodeMap = []
    var bufferLines: list<string> = []

    add(bufferLines, '#####################################################')
    add(bufferLines, '# ' .. toupper(fnamemodify(this.archivePath, ':t')))
    add(bufferLines, '# Press ? for keybindings help')
    add(bufferLines, '#####################################################')

    for _ in range(len(bufferLines))
      add(this.lineNodeMap, HeaderNode)
    endfor

    if this.showHelp
      var helpLines = [
        '# keybindings:',
        '# o, <CR> : open file or toggle dir',
        '# r       : refresh tree',
        '# q       : close window',
        '#####################################################'
      ]
      for hl in helpLines
        add(bufferLines, hl)
        add(this.lineNodeMap, HeaderNode)
      endfor
    endif

    if !empty(this.treeNodes)
      this.RenderNodeRecursive(this.treeNodes[0], 0, bufferLines)
    endif

    setline(1, bufferLines)
    setlocal nomodifiable
  enddef

  def RenderNodeRecursive(node: TarNode, indentLevel: number, lines: list<string>): void
    var indent = repeat('  ', indentLevel)
    var lineStr = ''

    if node.fullPath == ''
      lineStr = fnamemodify(this.archivePath, ':t:r') .. '/'
    else
      var arrow = ''
      if node.isDir
        arrow = node.expanded ? g:tartree_arrow_open : g:tartree_arrow_closed
      else
        arrow = '  '
      endif
      lineStr = indent .. arrow .. node.name .. (node.isDir ? '/' : '')
    endif

    add(lines, lineStr)
    add(this.lineNodeMap, node)

    if node.isDir && node.expanded && !empty(node.children)
      for child in node.children
        this.RenderNodeRecursive(child, indentLevel + 1, lines)
      endfor
    endif
  enddef

  def GetCurrentNode(): TarNode
    var lnum = line('.')
    if lnum <= len(this.lineNodeMap)
      return this.lineNodeMap[lnum - 1]
    endif
    return HeaderNode
  enddef
endclass

##############################################################################
# Singleton instance + autoload entry points 
##############################################################################
var instance: TarTreeWindow = TarTreeWindow.new()

export def Open(argPath: string = ''): void
  instance.Open(argPath)
enddef

export def AutoOpen(path: string): void
  instance.AutoOpen(path)
enddef

export def Toggle(): void
  instance.Toggle()
enddef

export def Close(): void
  instance.Close()
enddef

export def ActionOpen(): void
  instance.ActionOpen()
enddef

export def ActionRefresh(): void
  instance.ActionRefresh()
enddef

export def ToggleHelp(): void
  instance.ToggleHelp()
enddef
