local Sprites = {}

--Overlays with no DEPTH_<sheet>.png and no FloorOverlay flag fall back to
--DEPTH_whole_tile's box shape and get clipped. blends_grassoverlays_01 hit
--this and was removed. Check media/depthmaps/ before adding a new sheet.
Sprites.vanilla = {
    "d_streetcracks_1_48",  "d_streetcracks_1_49",  "d_streetcracks_1_50",
    "d_streetcracks_1_51",  "d_streetcracks_1_52",  "d_streetcracks_1_53",
    "d_streetcracks_1_54",  "d_streetcracks_1_55",  "d_streetcracks_1_56",
    "d_streetcracks_1_57",  "d_streetcracks_1_58",  "d_streetcracks_1_59",
    "d_streetcracks_1_60",  "d_streetcracks_1_61",  "d_streetcracks_1_62",
    "d_streetcracks_1_63",  "d_streetcracks_1_64",  "d_streetcracks_1_65",
    "d_streetcracks_1_66",  "d_streetcracks_1_67",  "d_streetcracks_1_68",
    "d_streetcracks_1_69",  "d_streetcracks_1_70",  "d_streetcracks_1_71",
    "d_streetcracks_1_72",  "d_streetcracks_1_73",  "d_streetcracks_1_74",
    "d_streetcracks_1_75",  "d_streetcracks_1_76",  "d_streetcracks_1_77",
    "d_streetcracks_1_78",  "d_streetcracks_1_79",  "d_streetcracks_1_80",
    "d_streetcracks_1_81",  "d_streetcracks_1_82",  "d_streetcracks_1_83",
    "d_streetcracks_1_84",  "d_streetcracks_1_85",  "d_streetcracks_1_86",
    "d_streetcracks_1_87",  "d_streetcracks_1_88",  "d_streetcracks_1_89",
    "d_streetcracks_1_90",  "d_streetcracks_1_91",  "d_streetcracks_1_92",
    "d_streetcracks_1_93",  "d_streetcracks_1_94",  "d_streetcracks_1_95",
    -- Valid flat grass-overlay frames; blank atlas cells are intentionally omitted.
    "e_newgrass_1_0",  "e_newgrass_1_1",  "e_newgrass_1_2",  "e_newgrass_1_3",
    "e_newgrass_1_4",  "e_newgrass_1_5",  "e_newgrass_1_8",  "e_newgrass_1_9",
    "e_newgrass_1_10", "e_newgrass_1_11", "e_newgrass_1_12", "e_newgrass_1_13",
    "e_newgrass_1_16", "e_newgrass_1_17", "e_newgrass_1_18", "e_newgrass_1_19",
    "e_newgrass_1_20", "e_newgrass_1_21", "e_newgrass_1_24", "e_newgrass_1_25",
    "e_newgrass_1_26", "e_newgrass_1_27", "e_newgrass_1_28", "e_newgrass_1_29",
    "e_newgrass_1_32", "e_newgrass_1_33", "e_newgrass_1_34", "e_newgrass_1_35",
    "e_newgrass_1_36", "e_newgrass_1_37", "e_newgrass_1_40", "e_newgrass_1_41",
    "e_newgrass_1_42", "e_newgrass_1_43", "e_newgrass_1_44", "e_newgrass_1_45",
    "e_newgrass_1_48", "e_newgrass_1_49", "e_newgrass_1_50", "e_newgrass_1_51",
    "e_newgrass_1_52", "e_newgrass_1_53", "e_newgrass_1_56", "e_newgrass_1_57",
    "e_newgrass_1_58", "e_newgrass_1_59", "e_newgrass_1_60", "e_newgrass_1_61",
    "d_plants_1_1",  "d_plants_1_2",  "d_plants_1_3",  "d_plants_1_4",
    "d_plants_1_5",  "d_plants_1_6",  "d_plants_1_7",
    "d_plants_1_16", "d_plants_1_17", "d_plants_1_18", "d_plants_1_19",
    "d_plants_1_20", "d_plants_1_21",
    "d_plants_1_32", "d_plants_1_33", "d_plants_1_34", "d_plants_1_35",
    "d_plants_1_37", "d_plants_1_38", "d_plants_1_39",
    "d_plants_1_49", "d_plants_1_50", "d_plants_1_51", "d_plants_1_52",
    "d_plants_1_53", "d_plants_1_55",
}

Sprites.custom = {
    "d_plants_1_40", "d_plants_1_41", "d_plants_1_42", "d_plants_1_43",
    "d_plants_1_44", "d_plants_1_45", "d_plants_1_46", "d_plants_1_47",
    "d_plants_1_57", "d_plants_1_58", "d_plants_1_59", "d_plants_1_60",
    "d_plants_1_61", "d_plants_1_62", "d_plants_1_63",
    "d_plants_1_24", "d_plants_1_25", "d_plants_1_26", "d_plants_1_27",
    "d_plants_1_28", "d_plants_1_29", "d_plants_1_30", "d_plants_1_31",
}

Sprites.leaves = {
    "d_floorleaves_1_0",  "d_floorleaves_1_1",  "d_floorleaves_1_2",
    "d_floorleaves_1_3",  "d_floorleaves_1_4",  "d_floorleaves_1_5",
    "d_floorleaves_1_6",  "d_floorleaves_1_7",  "d_floorleaves_1_8",
    "d_floorleaves_1_9",  "d_floorleaves_1_10", "d_floorleaves_1_11",
}

Sprites.debris = {
    "d_generic_1_8",  "d_generic_1_9",  "d_generic_1_10", "d_generic_1_11",
    "d_generic_1_12", "d_generic_1_13", "d_generic_1_14", "d_generic_1_15",
    "d_generic_1_16", "d_generic_1_17", "d_generic_1_18", "d_generic_1_19",
    "d_generic_1_20", "d_generic_1_21", "d_generic_1_22", "d_generic_1_23",
    "d_generic_1_24", "d_generic_1_25", "d_generic_1_26", "d_generic_1_27",
    "d_generic_1_28", "d_generic_1_29", "d_generic_1_30", "d_generic_1_31",
    "d_generic_1_32", "d_generic_1_33", "d_generic_1_34", "d_generic_1_35",
    "d_generic_1_36", "d_generic_1_37", "d_generic_1_38",
}

Sprites.trash = {
    "trash_01_0", "trash_01_1", "trash_01_2", "trash_01_3",
    "trash_01_4", "trash_01_5", "trash_01_6", "trash_01_7",
    "trash_01_8", "trash_01_9", "trash_01_10", "trash_01_11",
    "trash_01_12",
    "trash_01_16", "trash_01_17", "trash_01_18", "trash_01_19",
    "trash_01_20", "trash_01_21", "trash_01_22", "trash_01_23",
    "trash_01_24", "trash_01_25", "trash_01_26", "trash_01_27",
    "trash_01_28", "trash_01_29", "trash_01_30", "trash_01_31",
    "trash_01_32", "trash_01_33", "trash_01_34", "trash_01_35",
    "trash_01_36", "trash_01_37", "trash_01_38", "trash_01_39",
    "trash_01_40", "trash_01_41", "trash_01_42", "trash_01_43",
    "trash_01_44", "trash_01_45", "trash_01_46", "trash_01_47",
    "trash_01_48", "trash_01_49", "trash_01_50", "trash_01_51",
    "trash_01_52", "trash_01_53",
}

Sprites.crack = {
    "blends_streetoverlays_01_0", "blends_streetoverlays_01_1",
    "blends_streetoverlays_01_2", "blends_streetoverlays_01_3",
    "blends_streetoverlays_01_4", "blends_streetoverlays_01_5",
    "blends_streetoverlays_01_6", "blends_streetoverlays_01_7",
    "blends_streetoverlays_01_8", "blends_streetoverlays_01_9",
    "blends_streetoverlays_01_10", "blends_streetoverlays_01_11",
    "blends_streetoverlays_01_12", "blends_streetoverlays_01_13",
    "blends_streetoverlays_01_14", "blends_streetoverlays_01_15",
    "blends_streetoverlays_01_16", "blends_streetoverlays_01_17",
    "blends_streetoverlays_01_18", "blends_streetoverlays_01_19",
    "blends_streetoverlays_01_20", "blends_streetoverlays_01_21",
    "blends_streetoverlays_01_22", "blends_streetoverlays_01_23",
    "blends_streetoverlays_01_24", "blends_streetoverlays_01_25",
    "blends_streetoverlays_01_26", "blends_streetoverlays_01_27",
    "blends_streetoverlays_01_28", "blends_streetoverlays_01_29",
    "blends_streetoverlays_01_30", "blends_streetoverlays_01_31",
}

return Sprites
