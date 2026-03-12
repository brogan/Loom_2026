"""
XML I/O for SubdivisionConfig.
Reads and writes subdivision.xml files.
"""
from lxml import etree
from models.subdivision_config import (
    SubdivisionType, VisibilityRule, Vector2D, Range, RangeXY, Transform2D,
    SubdivisionParams, SubdivisionParamsSet, SubdivisionParamsSetCollection
)
from models.transform_config import (
    Range as TRange, ExteriorAnchorsConfig, CentralAnchorsConfig,
    AnchorsLinkedToCentreConfig, OuterControlPointsConfig,
    InnerControlPointsConfig, TransformSetConfig
)


class SubdivisionConfigIO:
    """Read and write subdivision configuration XML files."""

    @staticmethod
    def load(file_path: str) -> SubdivisionParamsSetCollection:
        """Load SubdivisionParamsSetCollection from an XML file."""
        tree = etree.parse(file_path)
        root = tree.getroot()
        return SubdivisionConfigIO._parse_config(root)

    @staticmethod
    def load_from_string(xml_content: str) -> SubdivisionParamsSetCollection:
        """Load SubdivisionParamsSetCollection from an XML string."""
        root = etree.fromstring(xml_content.encode())
        return SubdivisionConfigIO._parse_config(root)

    @staticmethod
    def save(collection: SubdivisionParamsSetCollection, file_path: str) -> None:
        """Save SubdivisionParamsSetCollection to an XML file."""
        root = SubdivisionConfigIO._build_xml(collection)
        tree = etree.ElementTree(root)
        tree.write(file_path, encoding="UTF-8", xml_declaration=True, pretty_print=True)

    @staticmethod
    def to_string(collection: SubdivisionParamsSetCollection) -> str:
        """Convert SubdivisionParamsSetCollection to XML string."""
        root = SubdivisionConfigIO._build_xml(collection)
        return etree.tostring(root, encoding="unicode", pretty_print=True)

    @staticmethod
    def _parse_config(root: etree._Element) -> SubdivisionParamsSetCollection:
        """Parse SubdivisionParamsSetCollection from XML element."""
        collection = SubdivisionParamsSetCollection()

        # Find SubdivisionParamsSet elements
        for ps_elem in root.findall(".//SubdivisionParamsSet"):
            params_set = SubdivisionConfigIO._parse_params_set(ps_elem)
            collection.add_params_set(params_set)

        return collection

    @staticmethod
    def _parse_params_set(elem: etree._Element) -> SubdivisionParamsSet:
        """Parse a SubdivisionParamsSet from XML element."""
        name = elem.get("name", "default")
        params_set = SubdivisionParamsSet(name=name)

        # Parse enabled params (direct children)
        for p_elem in elem.findall("SubdivisionParams"):
            params = SubdivisionConfigIO._parse_params(p_elem)
            params.enabled = True
            params_set.add_params(params)

        # Parse disabled params (inside EditorDisabled wrapper)
        disabled_elem = elem.find("EditorDisabled")
        if disabled_elem is not None:
            for p_elem in disabled_elem.findall("SubdivisionParams"):
                params = SubdivisionConfigIO._parse_params(p_elem)
                params.enabled = False
                params_set.add_params(params)

        return params_set

    @staticmethod
    def _parse_params(elem: etree._Element) -> SubdivisionParams:
        """Parse SubdivisionParams from XML element."""
        name = elem.get("name", "default")

        # Parse subdivision type
        sub_type_str = SubdivisionConfigIO._get_text(elem, "SubdivisionType", "QUAD")
        try:
            subdivision_type = SubdivisionType[sub_type_str]
        except KeyError:
            subdivision_type = SubdivisionType.QUAD

        # Parse visibility rule
        vis_rule_str = SubdivisionConfigIO._get_text(elem, "VisibilityRule", "ALL")
        try:
            visibility_rule = VisibilityRule[vis_rule_str]
        except KeyError:
            visibility_rule = VisibilityRule.ALL

        params = SubdivisionParams(
            name=name,
            subdivision_type=subdivision_type,
            visibility_rule=visibility_rule,
            ran_middle=SubdivisionConfigIO._get_bool(elem, "RanMiddle", False),
            ran_div=SubdivisionConfigIO._get_float(elem, "RanDiv", 100.0),
            line_ratios=SubdivisionConfigIO._parse_vector2d(elem, "LineRatios", Vector2D(0.5, 0.5)),
            control_point_ratios=SubdivisionConfigIO._parse_vector2d(elem, "ControlPointRatios", Vector2D(0.25, 0.75)),
            inset_transform=SubdivisionConfigIO._parse_transform2d(elem, "InsetTransform"),
            continuous=SubdivisionConfigIO._get_bool(elem, "Continuous", True),
            polys_transform=SubdivisionConfigIO._get_bool(elem, "PolysTransform", True),
            polys_transform_whole=SubdivisionConfigIO._get_bool(elem, "PolysTransformWhole", False),
            ptw_random_translation=SubdivisionConfigIO._get_bool(elem, "PTW_RandomTranslation", False),
            ptw_random_scale=SubdivisionConfigIO._get_bool(elem, "PTW_RandomScale", False),
            ptw_random_rotation=SubdivisionConfigIO._get_bool(elem, "PTW_RandomRotation", False),
            ptw_common_centre=SubdivisionConfigIO._get_bool(elem, "PTW_CommonCentre", False),
            ptw_probability=SubdivisionConfigIO._get_float(elem, "PTW_Probability", 100.0),
            ptw_transform=SubdivisionConfigIO._parse_transform2d(elem, "PTW_Transform"),
            ptw_random_centre_divisor=SubdivisionConfigIO._get_float(elem, "PTW_RandomCentreDivisor", 100.0),
            ptw_random_translation_range=SubdivisionConfigIO._parse_range_xy(elem, "PTW_RandomTranslationRange"),
            ptw_random_scale_range=SubdivisionConfigIO._parse_range_xy(elem, "PTW_RandomScaleRange", RangeXY(Range(1, 1), Range(1, 1))),
            ptw_random_rotation_range=SubdivisionConfigIO._parse_range(elem, "PTW_RandomRotationRange"),
            polys_transform_points=SubdivisionConfigIO._get_bool(elem, "PolysTransformPoints", False),
            ptp_probability=SubdivisionConfigIO._get_float(elem, "PTP_Probability", 100.0)
        )

        # Parse transform set
        transform_elem = elem.find("TransformSet")
        if transform_elem is not None:
            params.transform_set = SubdivisionConfigIO._parse_transform_set(transform_elem)

        return params

    @staticmethod
    def _parse_vector2d(parent: etree._Element, name: str, default: Vector2D = None) -> Vector2D:
        """Parse a Vector2D from XML element."""
        if default is None:
            default = Vector2D()
        elem = parent.find(name)
        if elem is None:
            return default
        x = float(elem.get("x", str(default.x)))
        y = float(elem.get("y", str(default.y)))
        return Vector2D(x, y)

    @staticmethod
    def _parse_range(parent: etree._Element, name: str, default: Range = None) -> Range:
        """Parse a Range from XML element."""
        if default is None:
            default = Range()
        elem = parent.find(name)
        if elem is None:
            return default
        min_val = float(elem.get("min", str(default.min_val)))
        max_val = float(elem.get("max", str(default.max_val)))
        return Range(min_val, max_val)

    @staticmethod
    def _parse_range_xy(parent: etree._Element, name: str, default: RangeXY = None) -> RangeXY:
        """Parse a RangeXY from XML element."""
        if default is None:
            default = RangeXY()
        elem = parent.find(name)
        if elem is None:
            return default
        x_range = SubdivisionConfigIO._parse_range(elem, "X", default.x)
        y_range = SubdivisionConfigIO._parse_range(elem, "Y", default.y)
        return RangeXY(x_range, y_range)

    @staticmethod
    def _parse_transform2d(parent: etree._Element, name: str) -> Transform2D:
        """Parse a Transform2D from XML element."""
        elem = parent.find(name)
        if elem is None:
            return Transform2D()
        translation = SubdivisionConfigIO._parse_vector2d(elem, "Translation", Vector2D(0, 0))
        scale = SubdivisionConfigIO._parse_vector2d(elem, "Scale", Vector2D(1, 1))
        rotation = SubdivisionConfigIO._parse_vector2d(elem, "Rotation", Vector2D(0, 0))
        return Transform2D(translation, scale, rotation)

    @staticmethod
    def _build_xml(collection: SubdivisionParamsSetCollection) -> etree._Element:
        """Build XML element from SubdivisionParamsSetCollection."""
        root = etree.Element("SubdivisionConfig", version="1.0")

        for params_set in collection.params_sets:
            ps_elem = etree.SubElement(root, "SubdivisionParamsSet", name=params_set.name)

            # Write enabled params as direct children (visible to Scala)
            for params in params_set.params_list:
                if params.enabled:
                    SubdivisionConfigIO._build_params(ps_elem, params)

            # Write disabled params inside EditorDisabled wrapper (invisible to Scala)
            disabled = [p for p in params_set.params_list if not p.enabled]
            if disabled:
                disabled_elem = etree.SubElement(ps_elem, "EditorDisabled")
                for params in disabled:
                    SubdivisionConfigIO._build_params(disabled_elem, params)

        return root

    @staticmethod
    def _build_params(parent: etree._Element, params: SubdivisionParams) -> None:
        """Build SubdivisionParams XML element."""
        elem = etree.SubElement(parent, "SubdivisionParams", name=params.name)

        SubdivisionConfigIO._add_element(elem, "SubdivisionType", params.subdivision_type.name)
        SubdivisionConfigIO._add_element(elem, "VisibilityRule", params.visibility_rule.name)
        SubdivisionConfigIO._add_element(elem, "RanMiddle", str(params.ran_middle).lower())
        SubdivisionConfigIO._add_element(elem, "RanDiv", str(params.ran_div))
        SubdivisionConfigIO._add_vector2d(elem, "LineRatios", params.line_ratios)
        SubdivisionConfigIO._add_vector2d(elem, "ControlPointRatios", params.control_point_ratios)
        SubdivisionConfigIO._add_transform2d(elem, "InsetTransform", params.inset_transform)
        SubdivisionConfigIO._add_element(elem, "Continuous", str(params.continuous).lower())
        SubdivisionConfigIO._add_element(elem, "PolysTransform", str(params.polys_transform).lower())
        SubdivisionConfigIO._add_element(elem, "PolysTransformWhole", str(params.polys_transform_whole).lower())
        SubdivisionConfigIO._add_element(elem, "PTW_RandomTranslation", str(params.ptw_random_translation).lower())
        SubdivisionConfigIO._add_element(elem, "PTW_RandomScale", str(params.ptw_random_scale).lower())
        SubdivisionConfigIO._add_element(elem, "PTW_RandomRotation", str(params.ptw_random_rotation).lower())
        SubdivisionConfigIO._add_element(elem, "PTW_CommonCentre", str(params.ptw_common_centre).lower())
        SubdivisionConfigIO._add_element(elem, "PTW_Probability", str(params.ptw_probability))
        SubdivisionConfigIO._add_transform2d(elem, "PTW_Transform", params.ptw_transform)
        SubdivisionConfigIO._add_element(elem, "PTW_RandomCentreDivisor", str(params.ptw_random_centre_divisor))
        SubdivisionConfigIO._add_range_xy(elem, "PTW_RandomTranslationRange", params.ptw_random_translation_range)
        SubdivisionConfigIO._add_range_xy(elem, "PTW_RandomScaleRange", params.ptw_random_scale_range)
        SubdivisionConfigIO._add_range(elem, "PTW_RandomRotationRange", params.ptw_random_rotation_range)
        SubdivisionConfigIO._add_element(elem, "PolysTransformPoints", str(params.polys_transform_points).lower())
        SubdivisionConfigIO._add_element(elem, "PTP_Probability", str(params.ptp_probability))

        # Build transform set
        if params.transform_set.has_any_enabled():
            SubdivisionConfigIO._build_transform_set(elem, params.transform_set)

    # --- Transform Set parsing ---

    @staticmethod
    def _parse_transform_set(elem: etree._Element) -> TransformSetConfig:
        """Parse TransformSetConfig from XML element."""
        ts = TransformSetConfig()

        ea_elem = elem.find("ExteriorAnchors")
        if ea_elem is not None:
            ts.exterior_anchors = SubdivisionConfigIO._parse_exterior_anchors(ea_elem)

        ca_elem = elem.find("CentralAnchors")
        if ca_elem is not None:
            ts.central_anchors = SubdivisionConfigIO._parse_central_anchors(ca_elem)

        al_elem = elem.find("AnchorsLinkedToCentre")
        if al_elem is not None:
            ts.anchors_linked = SubdivisionConfigIO._parse_anchors_linked(al_elem)

        ocp_elem = elem.find("OuterControlPoints")
        if ocp_elem is not None:
            ts.outer_control_points = SubdivisionConfigIO._parse_outer_control_points(ocp_elem)

        icp_elem = elem.find("InnerControlPoints")
        if icp_elem is not None:
            ts.inner_control_points = SubdivisionConfigIO._parse_inner_control_points(icp_elem)

        return ts

    @staticmethod
    def _parse_t_range(parent: etree._Element, name: str, default_min: float = 0.0, default_max: float = 0.0) -> TRange:
        """Parse a transform Range from XML element."""
        elem = parent.find(name)
        if elem is None:
            return TRange(default_min, default_max)
        return TRange(
            float(elem.get("min", str(default_min))),
            float(elem.get("max", str(default_max)))
        )

    @staticmethod
    def _parse_exterior_anchors(elem: etree._Element) -> ExteriorAnchorsConfig:
        """Parse ExteriorAnchorsConfig from XML."""
        g = SubdivisionConfigIO._get_text
        gb = SubdivisionConfigIO._get_bool
        gf = SubdivisionConfigIO._get_float
        pr = SubdivisionConfigIO._parse_t_range

        return ExteriorAnchorsConfig(
            enabled=elem.get("enabled", "false").lower() == "true",
            probability=gf(elem, "Probability", 100.0),
            spike_factor=gf(elem, "SpikeFactor", -0.3),
            which_spike=g(elem, "WhichSpike", "ALL"),
            spike_type=g(elem, "SpikeType", "SYMMETRICAL"),
            spike_axis=g(elem, "SpikeAxis", "XY"),
            random_spike=gb(elem, "RandomSpike", False),
            random_spike_factor=pr(elem, "RandomSpikeFactor", -0.2, 0.2),
            cps_follow=gb(elem, "CpsFollow", False),
            cps_follow_multiplier=gf(elem, "CpsFollowMultiplier", 2.0),
            random_cps_follow=gb(elem, "RandomCpsFollow", False),
            random_cps_follow_range=pr(elem, "RandomCpsFollowRange", -1.5, 1.5),
            cps_squeeze=gb(elem, "CpsSqueeze", False),
            cps_squeeze_factor=gf(elem, "CpsSqueezeFactor", -0.2),
            random_cps_squeeze=gb(elem, "RandomCpsSqueeze", False),
            random_cps_squeeze_range=pr(elem, "RandomCpsSqueezeRange", -0.5, 0.5)
        )

    @staticmethod
    def _parse_central_anchors(elem: etree._Element) -> CentralAnchorsConfig:
        """Parse CentralAnchorsConfig from XML."""
        g = SubdivisionConfigIO._get_text
        gb = SubdivisionConfigIO._get_bool
        gf = SubdivisionConfigIO._get_float
        pr = SubdivisionConfigIO._parse_t_range

        return CentralAnchorsConfig(
            enabled=elem.get("enabled", "false").lower() == "true",
            probability=gf(elem, "Probability", 100.0),
            tear_factor=gf(elem, "TearFactor", 0.2),
            tear_axis=g(elem, "TearAxis", "XY"),
            tear_direction=g(elem, "TearDirection", "DIAGONAL"),
            random_tear=gb(elem, "RandomTear", False),
            random_tear_factor=pr(elem, "RandomTearFactor", -0.2, 0.2),
            cps_follow=gb(elem, "CpsFollow", False),
            cps_follow_multiplier=gf(elem, "CpsFollowMultiplier", -7.0),
            random_cps_follow=gb(elem, "RandomCpsFollow", False),
            random_cps_follow_range=pr(elem, "RandomCpsFollowRange", -1.5, 1.5),
            all_points_follow=gb(elem, "AllPointsFollow", False),
            inverted_follow=gb(elem, "InvertedFollow", False)
        )

    @staticmethod
    def _parse_anchors_linked(elem: etree._Element) -> AnchorsLinkedToCentreConfig:
        """Parse AnchorsLinkedToCentreConfig from XML."""
        g = SubdivisionConfigIO._get_text
        gb = SubdivisionConfigIO._get_bool
        gf = SubdivisionConfigIO._get_float
        pr = SubdivisionConfigIO._parse_t_range

        return AnchorsLinkedToCentreConfig(
            enabled=elem.get("enabled", "false").lower() == "true",
            probability=gf(elem, "Probability", 100.0),
            tear_factor=gf(elem, "TearFactor", 0.45),
            tear_type=g(elem, "TearType", "TOWARDS_OUTSIDE_CORNER"),
            random_tear=gb(elem, "RandomTear", False),
            random_tear_factor=pr(elem, "RandomTearFactor", -0.2, 0.2),
            cps_follow=gb(elem, "CpsFollow", True),
            cps_follow_multiplier=gf(elem, "CpsFollowMultiplier", 1.0),
            random_cps_follow=gb(elem, "RandomCpsFollow", False),
            random_cps_follow_range=pr(elem, "RandomCpsFollowRange", -1.5, 1.5)
        )

    @staticmethod
    def _parse_outer_control_points(elem: etree._Element) -> OuterControlPointsConfig:
        """Parse OuterControlPointsConfig from XML."""
        g = SubdivisionConfigIO._get_text
        gb = SubdivisionConfigIO._get_bool
        gf = SubdivisionConfigIO._get_float
        pr = SubdivisionConfigIO._parse_t_range

        return OuterControlPointsConfig(
            enabled=elem.get("enabled", "false").lower() == "true",
            probability=gf(elem, "Probability", 100.0),
            line_ratio_x=gf(elem, "LineRatioX", 0.33),
            line_ratio_y=gf(elem, "LineRatioY", 0.66),
            random_line_ratio=gb(elem, "RandomLineRatio", False),
            random_line_ratio_inner=pr(elem, "RandomLineRatioInner", 0.1, 0.5),
            random_line_ratio_outer=pr(elem, "RandomLineRatioOuter", 0.5, 0.9),
            curve_mode=g(elem, "CurveMode", "PERPENDICULAR"),
            curve_type=g(elem, "CurveType", "PUFF"),
            curve_multiplier_min=gf(elem, "CurveMultiplierMin", 0.2),
            curve_multiplier_max=gf(elem, "CurveMultiplierMax", 0.2),
            random_multiplier=gb(elem, "RandomMultiplier", False),
            random_curve_multiplier=pr(elem, "RandomCurveMultiplier", 0.5, 3.0),
            curve_from_centre_ratio_x=gf(elem, "CurveFromCentreRatioX", 0.2),
            curve_from_centre_ratio_y=gf(elem, "CurveFromCentreRatioY", -0.5),
            random_from_centre=gb(elem, "RandomFromCentre", False),
            random_from_centre_a=pr(elem, "RandomFromCentreA", -1.0, 1.0),
            random_from_centre_b=pr(elem, "RandomFromCentreB", -1.0, 1.0)
        )

    @staticmethod
    def _parse_inner_control_points(elem: etree._Element) -> InnerControlPointsConfig:
        """Parse InnerControlPointsConfig from XML."""
        g = SubdivisionConfigIO._get_text
        gb = SubdivisionConfigIO._get_bool
        gf = SubdivisionConfigIO._get_float
        pr = SubdivisionConfigIO._parse_t_range

        return InnerControlPointsConfig(
            enabled=elem.get("enabled", "false").lower() == "true",
            probability=gf(elem, "Probability", 100.0),
            refer_to_outer=g(elem, "ReferToOuter", "NONE"),
            inner_multiplier_x=gf(elem, "InnerMultiplierX", 1.0),
            inner_multiplier_y=gf(elem, "InnerMultiplierY", 1.0),
            outer_multiplier_x=gf(elem, "OuterMultiplierX", 1.0),
            outer_multiplier_y=gf(elem, "OuterMultiplierY", 1.0),
            inner_ratio=gf(elem, "InnerRatio", -0.15),
            outer_ratio=gf(elem, "OuterRatio", 1.1),
            random_ratio=gb(elem, "RandomRatio", False),
            random_inner_ratio=pr(elem, "RandomInnerRatio", -0.5, 0.5),
            random_outer_ratio=pr(elem, "RandomOuterRatio", -0.5, 0.5),
            common_line=g(elem, "CommonLine", "EVEN")
        )

    # --- Transform Set building ---

    @staticmethod
    def _build_transform_set(parent: etree._Element, ts: TransformSetConfig) -> None:
        """Build TransformSet XML element."""
        ts_elem = etree.SubElement(parent, "TransformSet")

        if ts.exterior_anchors.enabled:
            SubdivisionConfigIO._build_exterior_anchors(ts_elem, ts.exterior_anchors)
        if ts.central_anchors.enabled:
            SubdivisionConfigIO._build_central_anchors(ts_elem, ts.central_anchors)
        if ts.anchors_linked.enabled:
            SubdivisionConfigIO._build_anchors_linked(ts_elem, ts.anchors_linked)
        if ts.outer_control_points.enabled:
            SubdivisionConfigIO._build_outer_control_points(ts_elem, ts.outer_control_points)
        if ts.inner_control_points.enabled:
            SubdivisionConfigIO._build_inner_control_points(ts_elem, ts.inner_control_points)

    @staticmethod
    def _add_t_range(parent: etree._Element, name: str, r: TRange) -> None:
        """Add a transform Range as XML element."""
        etree.SubElement(parent, name, min=str(r.min), max=str(r.max))

    @staticmethod
    def _build_exterior_anchors(parent: etree._Element, ea: ExteriorAnchorsConfig) -> None:
        """Build ExteriorAnchors XML element."""
        elem = etree.SubElement(parent, "ExteriorAnchors", enabled=str(ea.enabled).lower())
        SubdivisionConfigIO._add_element(elem, "Probability", str(ea.probability))
        SubdivisionConfigIO._add_element(elem, "SpikeFactor", str(ea.spike_factor))
        SubdivisionConfigIO._add_element(elem, "WhichSpike", ea.which_spike)
        SubdivisionConfigIO._add_element(elem, "SpikeType", ea.spike_type)
        SubdivisionConfigIO._add_element(elem, "SpikeAxis", ea.spike_axis)
        SubdivisionConfigIO._add_element(elem, "RandomSpike", str(ea.random_spike).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomSpikeFactor", ea.random_spike_factor)
        SubdivisionConfigIO._add_element(elem, "CpsFollow", str(ea.cps_follow).lower())
        SubdivisionConfigIO._add_element(elem, "CpsFollowMultiplier", str(ea.cps_follow_multiplier))
        SubdivisionConfigIO._add_element(elem, "RandomCpsFollow", str(ea.random_cps_follow).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomCpsFollowRange", ea.random_cps_follow_range)
        SubdivisionConfigIO._add_element(elem, "CpsSqueeze", str(ea.cps_squeeze).lower())
        SubdivisionConfigIO._add_element(elem, "CpsSqueezeFactor", str(ea.cps_squeeze_factor))
        SubdivisionConfigIO._add_element(elem, "RandomCpsSqueeze", str(ea.random_cps_squeeze).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomCpsSqueezeRange", ea.random_cps_squeeze_range)

    @staticmethod
    def _build_central_anchors(parent: etree._Element, ca: CentralAnchorsConfig) -> None:
        """Build CentralAnchors XML element."""
        elem = etree.SubElement(parent, "CentralAnchors", enabled=str(ca.enabled).lower())
        SubdivisionConfigIO._add_element(elem, "Probability", str(ca.probability))
        SubdivisionConfigIO._add_element(elem, "TearFactor", str(ca.tear_factor))
        SubdivisionConfigIO._add_element(elem, "TearAxis", ca.tear_axis)
        SubdivisionConfigIO._add_element(elem, "TearDirection", ca.tear_direction)
        SubdivisionConfigIO._add_element(elem, "RandomTear", str(ca.random_tear).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomTearFactor", ca.random_tear_factor)
        SubdivisionConfigIO._add_element(elem, "CpsFollow", str(ca.cps_follow).lower())
        SubdivisionConfigIO._add_element(elem, "CpsFollowMultiplier", str(ca.cps_follow_multiplier))
        SubdivisionConfigIO._add_element(elem, "RandomCpsFollow", str(ca.random_cps_follow).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomCpsFollowRange", ca.random_cps_follow_range)
        SubdivisionConfigIO._add_element(elem, "AllPointsFollow", str(ca.all_points_follow).lower())
        SubdivisionConfigIO._add_element(elem, "InvertedFollow", str(ca.inverted_follow).lower())

    @staticmethod
    def _build_anchors_linked(parent: etree._Element, al: AnchorsLinkedToCentreConfig) -> None:
        """Build AnchorsLinkedToCentre XML element."""
        elem = etree.SubElement(parent, "AnchorsLinkedToCentre", enabled=str(al.enabled).lower())
        SubdivisionConfigIO._add_element(elem, "Probability", str(al.probability))
        SubdivisionConfigIO._add_element(elem, "TearFactor", str(al.tear_factor))
        SubdivisionConfigIO._add_element(elem, "TearType", al.tear_type)
        SubdivisionConfigIO._add_element(elem, "RandomTear", str(al.random_tear).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomTearFactor", al.random_tear_factor)
        SubdivisionConfigIO._add_element(elem, "CpsFollow", str(al.cps_follow).lower())
        SubdivisionConfigIO._add_element(elem, "CpsFollowMultiplier", str(al.cps_follow_multiplier))
        SubdivisionConfigIO._add_element(elem, "RandomCpsFollow", str(al.random_cps_follow).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomCpsFollowRange", al.random_cps_follow_range)

    @staticmethod
    def _build_outer_control_points(parent: etree._Element, ocp: OuterControlPointsConfig) -> None:
        """Build OuterControlPoints XML element."""
        elem = etree.SubElement(parent, "OuterControlPoints", enabled=str(ocp.enabled).lower())
        SubdivisionConfigIO._add_element(elem, "Probability", str(ocp.probability))
        SubdivisionConfigIO._add_element(elem, "LineRatioX", str(ocp.line_ratio_x))
        SubdivisionConfigIO._add_element(elem, "LineRatioY", str(ocp.line_ratio_y))
        SubdivisionConfigIO._add_element(elem, "RandomLineRatio", str(ocp.random_line_ratio).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomLineRatioInner", ocp.random_line_ratio_inner)
        SubdivisionConfigIO._add_t_range(elem, "RandomLineRatioOuter", ocp.random_line_ratio_outer)
        SubdivisionConfigIO._add_element(elem, "CurveMode", ocp.curve_mode)
        SubdivisionConfigIO._add_element(elem, "CurveType", ocp.curve_type)
        SubdivisionConfigIO._add_element(elem, "CurveMultiplierMin", str(ocp.curve_multiplier_min))
        SubdivisionConfigIO._add_element(elem, "CurveMultiplierMax", str(ocp.curve_multiplier_max))
        SubdivisionConfigIO._add_element(elem, "RandomMultiplier", str(ocp.random_multiplier).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomCurveMultiplier", ocp.random_curve_multiplier)
        SubdivisionConfigIO._add_element(elem, "CurveFromCentreRatioX", str(ocp.curve_from_centre_ratio_x))
        SubdivisionConfigIO._add_element(elem, "CurveFromCentreRatioY", str(ocp.curve_from_centre_ratio_y))
        SubdivisionConfigIO._add_element(elem, "RandomFromCentre", str(ocp.random_from_centre).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomFromCentreA", ocp.random_from_centre_a)
        SubdivisionConfigIO._add_t_range(elem, "RandomFromCentreB", ocp.random_from_centre_b)

    @staticmethod
    def _build_inner_control_points(parent: etree._Element, icp: InnerControlPointsConfig) -> None:
        """Build InnerControlPoints XML element."""
        elem = etree.SubElement(parent, "InnerControlPoints", enabled=str(icp.enabled).lower())
        SubdivisionConfigIO._add_element(elem, "Probability", str(icp.probability))
        SubdivisionConfigIO._add_element(elem, "ReferToOuter", icp.refer_to_outer)
        SubdivisionConfigIO._add_element(elem, "InnerMultiplierX", str(icp.inner_multiplier_x))
        SubdivisionConfigIO._add_element(elem, "InnerMultiplierY", str(icp.inner_multiplier_y))
        SubdivisionConfigIO._add_element(elem, "OuterMultiplierX", str(icp.outer_multiplier_x))
        SubdivisionConfigIO._add_element(elem, "OuterMultiplierY", str(icp.outer_multiplier_y))
        SubdivisionConfigIO._add_element(elem, "InnerRatio", str(icp.inner_ratio))
        SubdivisionConfigIO._add_element(elem, "OuterRatio", str(icp.outer_ratio))
        SubdivisionConfigIO._add_element(elem, "RandomRatio", str(icp.random_ratio).lower())
        SubdivisionConfigIO._add_t_range(elem, "RandomInnerRatio", icp.random_inner_ratio)
        SubdivisionConfigIO._add_t_range(elem, "RandomOuterRatio", icp.random_outer_ratio)
        SubdivisionConfigIO._add_element(elem, "CommonLine", icp.common_line)

    @staticmethod
    def _add_element(parent: etree._Element, name: str, text: str) -> None:
        """Add a child element with text content."""
        elem = etree.SubElement(parent, name)
        elem.text = text

    @staticmethod
    def _add_vector2d(parent: etree._Element, name: str, vec: Vector2D) -> None:
        """Add a Vector2D as XML element."""
        etree.SubElement(parent, name, x=str(vec.x), y=str(vec.y))

    @staticmethod
    def _add_range(parent: etree._Element, name: str, r: Range) -> None:
        """Add a Range as XML element."""
        etree.SubElement(parent, name, min=str(r.min_val), max=str(r.max_val))

    @staticmethod
    def _add_range_xy(parent: etree._Element, name: str, rxy: RangeXY) -> None:
        """Add a RangeXY as XML element."""
        elem = etree.SubElement(parent, name)
        SubdivisionConfigIO._add_range(elem, "X", rxy.x)
        SubdivisionConfigIO._add_range(elem, "Y", rxy.y)

    @staticmethod
    def _add_transform2d(parent: etree._Element, name: str, t: Transform2D) -> None:
        """Add a Transform2D as XML element."""
        elem = etree.SubElement(parent, name)
        SubdivisionConfigIO._add_vector2d(elem, "Translation", t.translation)
        SubdivisionConfigIO._add_vector2d(elem, "Scale", t.scale)
        SubdivisionConfigIO._add_vector2d(elem, "Rotation", t.rotation)

    @staticmethod
    def _get_text(root: etree._Element, name: str, default: str) -> str:
        """Get text content of child element."""
        elem = root.find(name)
        if elem is not None and elem.text:
            return elem.text.strip()
        return default

    @staticmethod
    def _get_bool(root: etree._Element, name: str, default: bool) -> bool:
        """Get boolean value of child element."""
        text = SubdivisionConfigIO._get_text(root, name, "").lower()
        if text == "true":
            return True
        elif text == "false":
            return False
        return default

    @staticmethod
    def _get_float(root: etree._Element, name: str, default: float) -> float:
        """Get float value of child element."""
        text = SubdivisionConfigIO._get_text(root, name, "")
        if text:
            try:
                return float(text)
            except ValueError:
                pass
        return default
