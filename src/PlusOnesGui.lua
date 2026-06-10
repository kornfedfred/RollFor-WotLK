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

local FRAME_WIDTH   = 600
local FRAME_HEIGHT  = 460
local COL_PLAYER    = 160
local COL_ITEM      = 300
local COL_COUNT     = 80
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
  title:SetText( string.format( "%s  —  +1s (MainSpec Awards)", m.colors.blue( "RollFor" ) ) )

  -- Inner backdrop
  local inner = m.create_backdrop_frame( api(), "Frame", nil, frame )
  inner:SetBackdrop( control_backdrop )
  inner:SetBackdropColor( 0, 0, 0 )
  inner:SetBackdropBorderColor( 0.4, 0.4, 0.4 )
  inner:SetPoint( "TOPLEFT",     frame, "TOPLEFT",     17,  -32 )
  inner:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17,  43 )

  -- Column header bar
  local header_bar = api().CreateFrame( "Frame", nil, inner )
  header_bar:SetPoint( "TOPLEFT",  inner, "TOPLEFT",  4,   -4 )
  header_bar:SetPoint( "TOPRIGHT", inner, "TOPRIGHT", -22, -4 )
  header_bar:SetHeight( HEADER_HEIGHT )

  local header_bg = header_bar:CreateTexture( nil, "BACKGROUND" )
  header_bg:SetAllPoints()
  header_bg:SetTexture( 0.15, 0.15, 0.15, 1 )

  local function make_header_cell( label, x, width )
    local fs = header_bar:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
    fs:SetPoint( "LEFT", header_bar, "LEFT", x + 4, 0 )
    fs:SetWidth( width - 8 )
    fs:SetJustifyH( "LEFT" )
    fs:SetText( m.colors.white( label ) )
  end

  make_header_cell( "Player", 0,                     COL_PLAYER )
  make_header_cell( "Item",   COL_PLAYER,             COL_ITEM )
  make_header_cell( "+1s",    COL_PLAYER + COL_ITEM,  COL_COUNT )

  -- Scroll frame
  local scroll_frame = api().CreateFrame( "ScrollFrame", "RollForPlusOnesScroll", inner, "UIPanelScrollFrameTemplate" )
  scroll_frame:SetPoint( "TOPLEFT",     header_bar, "BOTTOMLEFT",  0,   -2 )
  scroll_frame:SetPoint( "BOTTOMRIGHT", inner,      "BOTTOMRIGHT", -22,  4 )

  local scroll_child = api().CreateFrame( "Frame", nil, scroll_frame )
  scroll_frame:SetScrollChild( scroll_child )
  scroll_child:SetWidth( 1 )
  scroll_child:SetHeight( 1 )

  -- Row pool
  local row_pool = {}

  local function acquire_row( index )
    local row = row_pool[ index ]
    if not row then
      row = api().CreateFrame( "Frame", nil, scroll_child )
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

      row.cell_player = make_cell( 0,                     COL_PLAYER )
      row.cell_item   = make_cell( COL_PLAYER,             COL_ITEM )
      row.cell_count  = make_cell( COL_PLAYER + COL_ITEM,  COL_COUNT, "CENTER" )

      -- Remove button (tiny "X")
      local remove_btn = api().CreateFrame( "Button", nil, row )
      remove_btn:SetWidth( 14 )
      remove_btn:SetHeight( 14 )
      remove_btn:SetPoint( "RIGHT", row, "RIGHT", -4, 0 )
      local remove_text = remove_btn:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
      remove_text:SetAllPoints()
      remove_text:SetText( m.colors.red( "✕" ) )
      remove_btn:SetScript( "OnEnter", function()
        remove_btn:GetParent().bg:SetTexture( 0.4, 0.1, 0.1, 0.5 )
      end )
      remove_btn:SetScript( "OnLeave", function()
        -- bg will be reset on next render_rows call; just dim back
        remove_btn:GetParent().bg:SetTexture( 0.12, 0.06, 0.06, 0.8 )
      end )
      row.remove_btn = remove_btn

      row_pool[ index ] = row
    end
    return row
  end

  -- last_rows: list of { player_name, player_class, item_link, item_id, count }
  local last_rows = {}

  local function render_rows()
    local total_width = scroll_frame:GetWidth()

    for i, data in ipairs( last_rows ) do
      local row = acquire_row( i )
      row:ClearAllPoints()
      row:SetPoint( "TOPLEFT", scroll_child, "TOPLEFT", 0, -( (i - 1) * ROW_HEIGHT ) )
      row:SetWidth( total_width )
      row:Show()

      if i % 2 == 0 then
        row.bg:SetTexture( 0.10, 0.05, 0.05, 0.8 )
      else
        row.bg:SetTexture( 0.06, 0.03, 0.03, 0.8 )
      end

      local player_text = data.player_name
      if group_roster then
        local p = group_roster.find_player( data.player_name )
        if p and p.class then
          player_text = m.colorize_player_by_class( data.player_name, p.class )
        elseif data.player_class then
          player_text = m.colorize_player_by_class( data.player_name, data.player_class )
        end
      end

      row.cell_player:SetText( player_text )
      row.cell_item:SetText( data.item_link or m.colors.grey( tostring( data.item_id ) ) )
      row.cell_count:SetText( m.colors.green( tostring( data.count ) ) )

      -- Wire up the remove button for this specific row
      local captured = data
      row.remove_btn:SetScript( "OnClick", function()
        confirm_popup.show(
          { "Remove +1 for " .. ( captured.item_link or "this item" ) .. " from " .. captured.player_name .. "?", "Are you sure?" },
          function( yes )
            if yes then
              -- Find the DB index for this specific plus_one entry and unaward it.
              -- We unaward by scanning awarded_items for a matching plus_one entry.
              local all = awarded_loot.get_winners()
              for idx = #all, 1, -1 do
                local entry = all[ idx ]
                if entry.player_name == captured.player_name
                    and entry.item_id == captured.item_id
                    and entry.plus_one then
                  awarded_loot.update_item( idx, { plus_one = false } )
                  break
                end
              end
              frame.rebuild()
            end
          end
        )
      end )
      row.remove_btn:Show()
    end

    -- Hide surplus rows
    for i = #last_rows + 1, #row_pool do
      if row_pool[ i ] then row_pool[ i ]:Hide() end
    end

    scroll_child:SetHeight( math.max( 1, #last_rows * ROW_HEIGHT ) )
    scroll_child:SetWidth( math.max( 1, total_width ) )
    scroll_frame:UpdateScrollChildRect()
    scroll_frame:SetVerticalScroll( 0 )
  end

  -- Build the flat list of +1 entries from awarded_loot.
  local function build_rows()
    local rows = {}
    local all = awarded_loot.get_winners()

    for _, entry in ipairs( all ) do
      if entry.plus_one then
        table.insert( rows, {
          player_name  = entry.player_name,
          player_class = entry.player_class,
          item_id      = entry.item_id,
          item_link    = entry.item_link,
          count        = 1,  -- one entry = one +1
        } )
      end
    end

    -- Sort by player name then item
    table.sort( rows, function( a, b )
      if a.player_name ~= b.player_name then return a.player_name < b.player_name end
      return ( a.item_id or 0 ) < ( b.item_id or 0 )
    end )

    -- Collapse: merge consecutive same-player+item entries into a count
    local collapsed = {}
    for _, row in ipairs( rows ) do
      local last = collapsed[ #collapsed ]
      if last and last.player_name == row.player_name and last.item_id == row.item_id then
        last.count = last.count + 1
      else
        table.insert( collapsed, {
          player_name  = row.player_name,
          player_class = row.player_class,
          item_id      = row.item_id,
          item_link    = row.item_link,
          count        = 1,
        } )
      end
    end

    return collapsed
  end

  function frame.rebuild()
    last_rows = build_rows()
    render_rows()

    -- Update status label
    local total = 0
    for _, r in ipairs( last_rows ) do total = total + r.count end
    if total == 0 then
      frame.status_label:SetText( m.colors.grey( "No +1s recorded yet." ) )
    else
      frame.status_label:SetText( string.format( "%s total +1%s across %s player%s.",
        m.colors.green( tostring( total ) ),
        total == 1 and "" or "s",
        m.colors.hl( tostring( #last_rows ) ),
        #last_rows == 1 and "" or "s"
      ) )
    end
  end

  -- Status / summary label at bottom
  local status_label = frame:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
  status_label:SetPoint( "BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22 )
  status_label:SetTextColor( 0.7, 0.7, 0.7, 1 )
  frame.status_label = status_label

  -- "Clear all" button
  local clear_btn = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  clear_btn:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -27, 17 )
  clear_btn:SetHeight( 20 )
  clear_btn:SetWidth( 90 )
  clear_btn:SetText( "Clear All" )
  clear_btn:SetScript( "OnClick", function()
    confirm_popup.show(
      { "This will remove ALL +1s.", "Are you sure?" },
      function( yes )
        if yes then
          local all = awarded_loot.get_winners()
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
