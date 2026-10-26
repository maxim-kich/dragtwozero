"""The existing Drag installer layout, written without Finder automation."""
import os

files = [os.environ['DRAGTWOZERO_DMG_APP']]
symlinks = {'Applications': '/Applications'}
background = os.environ['DRAGTWOZERO_DMG_BACKGROUND']
format = 'UDZO'
filesystem = 'HFS+'
window_rect = ((180, 140), (720, 488))
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
grid_spacing = 80
icon_size = 88
text_size = 13
label_pos = 'bottom'
icon_locations = {'Drag 2.0 (Alpha).app': (225, 237), 'Applications': (495, 237)}
