RollFor = RollFor or {}
local m = RollFor

if m.PlusOnesGui then return end

local M = {}

---@diagnostic disable-next-line: undefined-global
local UIParent = UIParent

local frame_backdrop = {
  bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile     = true,
  tileSize = 32,
  edgeSize = 32,
  insets   = { left = 8, right = 8, top = 8, bottom = 8 }
}

local control_backdrop = {
  bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile     = true,
  tileSize = 16,
  edgeSize = 16,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 }
}

local FRAME_WIDTH   = 580
local FRAME_HEIGHT  = 460
local COL_PLAYER    = 160
local COL_COUNT     = 50
local COL_ITEM      = 310   -- remaining width after player + count + scrollbar
local ROW_HEIGHT    = 18
local HEADER_HEIGHT = 22

-- ---------------------------------------------------------------------------
-- Table frame
-- ---------------------------------------------------------------------------

local function create_table_frame( api, awarded_loot, group_roster, confirm_popup )
  local frame = m.create_backdrop_frame( api(), "Frame", "RollForPlusOnesFrame", UIParent )
  frame:Hide()
  frame:SetWidth( FRAME_WIDTH )
  frame:SetHeight( FRAME_HEIGHT )
  frame:SetPoint( "CENTER", UIParent, "CENTER", 0, 0 )
  frame:EnableMouse( true )
  frame:SetMovable( true )
  frame:SetFrameStrata( "DIALOG" )
  frame:SetBackdrop( frame_backdrop )
  frame:SetBackdropColor( 0, 0, 0, 1 )
  frame:SetToplevel( true )

  local close_button = api().CreateFrame( "Button", nil, frame, "UIPanelCloseButton" )
  close_button:SetPoint( "TOPRIGHT", frame, "TOPRIGHT", 0, 0 )
  close_button:SetScript( "OnClick", function() frame:Hide() end )

  local title = frame:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
  title:SetPoint( "TOPLEFT", frame, "TOPLEFT", 20, -14 )
  title:SetTextColor( 1, 1, 1, 1 )
  title:SetText( string.format( "%s  —  +1s", m.colors.blue( "RollFor" ) ) )

  -- Inner content area
  local inner = m.create_backdrop_frame( api(), "Frame", nil, frame )
  inner:SetBackdrop( control_backdrop )
  inner:SetBackdropColor( 0, 0, 0 )
  inner:SetBackdropBorderColor( 0.4, 0.4, 0.4 )
  inner:SetPoint( "TOPLEFT",     frame, "TOPLEFT",     17, -32 )
  inner:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17,  43 )

  -- Column headers
  local header_bar = api().CreateFrame( "Frame", nil, inner )
  header_bar:SetPoint( "TOPLEFT",  inner, "TOPLEFT",  4,   -4 )
  header_bar:SetPoint( "TOPRIGHT", inner, "TOPRIGHT", -22, -4 )
  header_bar:SetHeight( HEADER_HEIGHT )

  local header_bg = header_bar:CreateTexture( nil, "BACKGROUND" )
  header_bg:SetAllPoints()
  header_bg:SetTexture( 0.15, 0.15, 0.15, 1 )

  local function make_header_cell( label, x, width, justify )
    local fs = header_bar:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
    fs:SetPoint( "LEFT", header_bar, "LEFT", x + 4, 0 )
    fs:SetWidth( width - 8 )
    fs:SetJustifyH( justify or "LEFT" )
    fs:SetText( m.colors.white( label ) )
  end

  make_header_cell( "Player",         0,                       COL_PLAYER )
  make_header_cell( "+1s",            COL_PLAYER,              COL_COUNT, "CENTER" )
  make_header_cell( "Items Received", COL_PLAYER + COL_COUNT,  COL_ITEM )

  -- Scroll frame
  local scroll_frame = api().CreateFrame( "ScrollFrame", "RollForPlusOnesScroll", inner, "UIPanelScrollFrameTemplate" )
  scroll_frame:SetPoint( "TOPLEFT",     header_bar, "BOTTOMLEFT",  0,   -2 )
  scroll_frame:SetPoint( "BOTTOMRIGHT", inner,      "BOTTOMRIGHT", -22,  4 )

  local scroll_child = api().CreateFrame( "Frame", nil, scroll_frame )
  scroll_frame:SetScrollChild( scroll_child )
  scroll_child:SetWidth( 1 )
  scroll_child:SetHeight( 1 )

  -- ---------------------------------------------------------------------------
  -- Row pool — two row types:
  --   "player" rows: name, +1 count, remove-latest button
  --   "item"   rows: indented item link (sub-rows under a player)
  -- ---------------------------------------------------------------------------
  local row_pool = {}

  local function acquire_row( index )
    if not row_pool[ index ] then
      local row = api().CreateFrame( "Frame", nil, scroll_child )
      row:SetHeight( ROW_HEIGHT )

      local bg = row:CreateTexture( nil, "BACKGROUND" )
      bg:SetAllPoints()
      row.bg = bg

      local function make_cell( x, w, justify )
        local fs = row:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
        fs:SetPoint( "LEFT", row, "LEFT", x + 4, 0 )
        fs:SetWidth( w - 8 )
        fs:SetJustifyH( justify or "LEFT" )
        return fs
      end

      -- Player-row cells
      row.cell_player = make_cell( 0,            COL_PLAYER )
      row.cell_count  = make_cell( COL_PLAYER,   COL_COUNT, "CENTER" )
      row.cell_item   = make_cell( COL_PLAYER + COL_COUNT, COL_ITEM )

      -- Remove button (only used on player rows)
      local remove_btn = api().CreateFrame( "Button", nil, row )
      remove_btn:SetWidth( 14 )
      remove_btn:SetHeight( 14 )
      remove_btn:SetPoint( "RIGHT", row, "RIGHT", -4, 0 )
      local remove_fs = remove_btn:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
      remove_fs:SetAllPoints()
      remove_fs:SetText( m.colors.red( "x" ) )
      row.remove_btn  = remove_btn
      row.remove_fs   = remove_fs

      row_pool[ index ] = row
    end
    return row_pool[ index ]
  end

  -- last_rows: flat list built by build_rows(); each entry has a "kind" field
  local last_rows = {}

  local function render_rows()
    local total_width = scroll_frame:GetWidth()

    for i, data in ipairs( last_rows ) do
      local row = acquire_row( i )
      row:ClearAllPoints()
      row:SetPoint( "TOPLEFT", scroll_child, "TOPLEFT", 0, -( (i - 1) * ROW_HEIGHT ) )
      row:SetWidth( total_width )
      row:Show()

      if data.kind == "player" then
        -- Alternating stripe based on player index
        if data.stripe % 2 == 0 then
          row.bg:SetTexture( 0.10, 0.05, 0.05, 0.9 )
        else
          row.bg:SetTexture( 0.06, 0.03, 0.03, 0.9 )
        end

        local player_text = data.player_name
        if data.player_class then
          player_text = m.colorize_player_by_class( data.player_name, data.player_class )
        end

        row.cell_player:SetText( player_text )
        row.cell_count:SetText( m.colors.green( tostring( data.count ) ) )
        row.cell_item:SetText( "" )

        -- Wire up remove button: removes the most recent +1 for this player
        local captured = data
        row.remove_btn:SetScript( "OnClick", function()
          local last = captured.items[ #captured.items ]
          if not last then return end
          confirm_popup.show(
            { "Remove latest +1 for " .. captured.player_name .. "?",
              ( last.item_link or "Unknown item" ) },
            function( yes )
              if yes then
                -- Preserve scroll position across rebuild
                local scroll_pos = scroll_frame:GetVerticalScroll()
                awarded_loot.update_item( last.db_idx, { plus_one = false } )
                frame.rebuild( scroll_pos )
              end
            end
          )
        end )

        -- Hover: highlight whole row stripe
        row.remove_btn:SetScript( "OnEnter", function()
          row.bg:SetTexture( 0.35, 0.10, 0.10, 0.9 )
        end )
        row.remove_btn:SetScript( "OnLeave", function()
          -- Restore correct stripe colour
          if data.stripe % 2 == 0 then
            row.bg:SetTexture( 0.10, 0.05, 0.05, 0.9 )
          else
            row.bg:SetTexture( 0.06, 0.03, 0.03, 0.9 )
          end
        end )
        row.remove_btn:Show()

      elseif data.kind == "item" then
        -- Sub-row: slightly lighter shade, indented item link
        if data.stripe % 2 == 0 then
          row.bg:SetTexture( 0.08, 0.04, 0.04, 0.7 )
        else
          row.bg:SetTexture( 0.05, 0.02, 0.02, 0.7 )
        end

        row.cell_player:SetText( "" )
        row.cell_count:SetText( "" )
        -- Indent item link into the item column
        row.cell_item:SetText( "  " .. ( data.item_link or m.colors.grey( "Unknown item" ) ) )
        row.remove_btn:Hide()
        row.remove_btn:SetScript( "OnClick", nil )
      end
    end

    -- Hide surplus pooled rows
    for i = #last_rows + 1, #row_pool do
      row_pool[ i ]:Hide()
    end

    scroll_child:SetHeight( math.max( 1, #last_rows * ROW_HEIGHT ) )
    scroll_child:SetWidth( math.max( 1, total_width ) )
    scroll_frame:UpdateScrollChildRect()
  end

  -- ---------------------------------------------------------------------------
  -- build_rows: collapse awarded_loot into player buckets, then flatten into
  -- a mixed list of "player" header rows and "item" sub-rows.
  -- ---------------------------------------------------------------------------
  local function build_rows()
    local player_map  = {}
    local player_order = {}
    local all = awarded_loot.get_winners()

    for idx, entry in ipairs( all ) do
      if entry and entry.plus_one then
        local name = entry.player_name
        if not player_map[ name ] then
          player_map[ name ] = {
            player_name  = name,
            player_class = entry.player_class,
            count        = 0,
            items        = {},
          }
          table.insert( player_order, name )
        end
        local bucket = player_map[ name ]
        bucket.count = bucket.count + 1
        table.insert( bucket.items, {
          item_link = entry.item_link,
          db_idx    = idx,
        } )
      end
    end

    table.sort( player_order, function( a, b ) return a < b end )

    local flat = {}
    for stripe, name in ipairs( player_order ) do
      local bucket = player_map[ name ]

      -- Resolve class from GroupRoster if missing in DB entry
      local resolved_class = bucket.player_class
      if not resolved_class and group_roster then
        local p = group_roster.find_player( name )
        resolved_class = p and p.class
      end

      table.insert( flat, {
        kind         = "player",
        stripe       = stripe,
        player_name  = name,
        player_class = resolved_class,
        count        = bucket.count,
        items        = bucket.items,
      } )

      for _, item in ipairs( bucket.items ) do
        table.insert( flat, {
          kind      = "item",
          stripe    = stripe,
          item_link = item.item_link,
        } )
      end
    end

    return flat
  end

  -- Rebuild and re-render; optionally restore scroll position.
  function frame.rebuild( restore_scroll )
    last_rows = build_rows()
    render_rows()

    -- Count totals for status bar
    local total_plus_ones = 0
    local total_players   = 0
    for _, r in ipairs( last_rows ) do
      if r.kind == "player" then
        total_players   = total_players + 1
        total_plus_ones = total_plus_ones + r.count
      end
    end

    if total_plus_ones == 0 then
      frame.status_label:SetText( m.colors.grey( "No +1s recorded yet." ) )
    else
      frame.status_label:SetText( string.format(
        "%s total +1%s across %s player%s.",
        m.colors.green( tostring( total_plus_ones ) ),
        total_plus_ones == 1 and "" or "s",
        m.colors.hl( tostring( total_players ) ),
        total_players   == 1 and "" or "s"
      ) )
    end

    if restore_scroll then
      scroll_frame:SetVerticalScroll( restore_scroll )
    else
      scroll_frame:SetVerticalScroll( 0 )
    end
  end

  -- Status label
  local status_label = frame:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
  status_label:SetPoint( "BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22 )
  status_label:SetTextColor( 0.7, 0.7, 0.7, 1 )
  frame.status_label = status_label

  -- "Clear All" button
  local clear_btn = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  clear_btn:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -27, 17 )
  clear_btn:SetHeight( 20 )
  clear_btn:SetWidth( 90 )
  clear_btn:SetText( "Clear All" )
  clear_btn:SetScript( "OnClick", function()
    confirm_popup.show(
      { "Remove ALL +1s?", "This cannot be undone." },
      function( yes )
        if yes then
          local all = awarded_loot.get_winners()
          -- Iterate in reverse so index-based updates don't shift subsequent entries.
          -- update_item mutates in-place so indices stay stable; reverse is just
          -- defensive practice and matches the original pattern.
          for idx = #all, 1, -1 do
            if all[ idx ] and all[ idx ].plus_one then
              awarded_loot.update_item( idx, { plus_one = false } )
            end
          end
          frame.rebuild()
        end
      end
    )
  end )

  ---@diagnostic disable-next-line: undefined-global
  table.insert( UISpecialFrames, "RollForPlusOnesFrame" )
  return frame
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

function M.new( api, awarded_loot, group_roster, confirm_popup )
  local table_frame

  local function show()
    if not table_frame then
      table_frame = create_table_frame( api, awarded_loot, group_roster, confirm_popup )
    end
    table_frame.rebuild()
    table_frame:Show()
  end

  local function hide()
    if table_frame then table_frame:Hide() end
  end

  local function toggle()
    if table_frame and table_frame:IsVisible() then
      hide()
    else
      show()
    end
  end

  return {
    show   = show,
    hide   = hide,
    toggle = toggle,
  }
end

m.PlusOnesGui = M
return M