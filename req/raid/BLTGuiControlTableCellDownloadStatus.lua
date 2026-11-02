BLTGuiControlTableCellDownloadStatus = BLTGuiControlTableCellDownloadStatus or blt_class(RaidGUIControl)
BLTGuiControlTableCellDownloadStatus.FONT = tweak_data.gui.fonts.din_compressed
BLTGuiControlTableCellDownloadStatus.FONT_SIZE = tweak_data.gui.font_sizes.small

function BLTGuiControlTableCellDownloadStatus:init(parent, params, cell_data, table_params)
	params.font = params.font or BLTGuiControlTableCellDownloadStatus.FONT
	params.font_size = params.font_size or BLTGuiControlTableCellDownloadStatus.FONT_SIZE

	BLTGuiControlTableCellDownloadStatus.super.init(self, parent, params)

	self._table_params = table_params
	self._data = {
		value = params.value,
	}

	self._object = self._panel:panel({
		w = params.w,
		h = params.height,
		layer = params.layer,
		x = params.x,
		y = params.y,
	})

	self._text = self._object:label({
		w = params.w,
		h = params.height,
		layer = params.layer + 1,
		x = 0,
		text = params.text,
		font = params.font,
		font_size = params.font_size,
		fit_text = true,
		color = self._table_params.row_params.highlight_color,
	})
	self._text:set_center_y(params.height / 2)

	self._progress = self._object:progress_bar_simple({
		w = params.w - 32,
		h = 4,
		layer = params.layer + 1,
		x = 0,
		bar_width = params.w - 32,
		border_width = 1,
		left = "slider_large_left",
		center = "slider_large_center",
		right = "slider_large_right",
	})
	self._progress:set_bottom(params.height - 16)

	BLT.Downloads:register_event_handler(BLT.Downloads.EVENTS.download_state_changed,
		"blt_downloads_gui_list_on_download_state_changed" .. params.value.update:GetName(),
		callback(self, self, "_on_download_state_changed"),
		params.value.update)
end

function BLTGuiControlTableCellDownloadStatus:close()
	BLT.Downloads:remove_event_handler(BLT.Downloads.EVENTS.download_state_changed,
		"blt_downloads_gui_list_on_download_state_changed" .. self._params.value.update:GetName())
end

function BLTGuiControlTableCellDownloadStatus:highlight_on()
	if self._text and self._table_params and self._table_params.row_params and self._table_params.row_params.color and self._table_params.row_params.highlight_color then
		self._text:set_color(self._table_params.row_params.highlight_color)
	end
end

function BLTGuiControlTableCellDownloadStatus:highlight_off()
	if self._text and self._table_params and self._table_params.row_params and self._table_params.row_params.color and self._table_params.row_params.highlight_color then
		self._text:set_color(self._table_params.row_params.highlight_color)
	end
end

function BLTGuiControlTableCellDownloadStatus:select_on()
	if self._text and self._params.selected_color and self._params.color then
		self._text:set_color(self._params.selected_color)
	end
end

function BLTGuiControlTableCellDownloadStatus:select_off()
	if self._text and self._params.selected_color and self._params.color then
		self._text:set_color(self._params.color)
	end
end

function BLTGuiControlTableCellDownloadStatus:on_double_click(button)
	if self._params.on_double_click_callback then
		self._params.on_double_click_callback(button, self, self._data)
	end
end

function BLTGuiControlTableCellDownloadStatus:_on_download_state_changed(download)
	local percent = math.min((download.bytes or 0) / math.max(download.total_bytes or 0, 1), 1)
	if download.state == "complete" then
		self:_update_complete(download, percent)
	elseif download.state == "failed" then
		self:_update_failed(download, percent)
	elseif download.state == "verifying" then
		self:_update_verifying(download, percent)
	elseif download.state == "extracting" then
		self:_update_extracting(download, percent)
	elseif download.state == "saving" then
		self:_update_saving(download, percent)
	elseif download.state == "downloading" then
		self:_update_download(download, percent)
	elseif download.state == "waiting" then
		self:_update_waiting(download, percent)
	end
end

function BLTGuiControlTableCellDownloadStatus:_update_complete(download, percent)
	self._text:set_text(self:translate("blt_download_done"))
end

function BLTGuiControlTableCellDownloadStatus:_update_failed(download, percent)
	self._text:set_text(self:translate("blt_download_failed"))
end

function BLTGuiControlTableCellDownloadStatus:_update_verifying(download, percent)
	self._text:set_text(self:translate("blt_download_verifying"))
end

function BLTGuiControlTableCellDownloadStatus:_update_extracting(download, percent)
	self._text:set_text(self:translate("blt_download_extracting"))
end

function BLTGuiControlTableCellDownloadStatus:_update_saving(download, percent)
	self._text:set_text(self:translate("blt_download_saving"))
end

function BLTGuiControlTableCellDownloadStatus:_update_download(download, progress)
	local current = download.bytes / 1024
	local total = download.total_bytes / 1024
	local unit = "KB"
	if total > 1024 then
		current = current / 1024
		total = total / 1024
		unit = "MB"
	end
	local macros = {
		current = string.format("%.1f", current),
		total = string.format("%.1f", total),
		unit = unit
	}
	self._text:set_text(self:translate("blt_download_downloading", false, macros))
	self._progress:set_progress(progress)
end

function BLTGuiControlTableCellDownloadStatus:_update_waiting(download, progress)
	self._text:set_text(self:translate("blt_download_waiting"))
end
