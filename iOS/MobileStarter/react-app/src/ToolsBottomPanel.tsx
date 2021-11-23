/*---------------------------------------------------------------------------------------------
* Copyright (c) 2020 Bentley Systems, Incorporated. All rights reserved.
*--------------------------------------------------------------------------------------------*/
import * as React from "react";
import classnames from "classnames";
import {
  CoreTools,
  ToolItemDef
} from "@bentley/ui-framework";
import {
  imageElementFromUrl,
  IModelApp,
  IModelConnection,
  Tool,
  ToolSettings,
} from "@bentley/imodeljs-frontend";
import {
  MeasureToolDefinitions
} from "@bentley/measure-tools-react";
import { Point3d } from "@bentley/geometry-core";
import {
  assignRef,
  BottomPanel,
  BottomPanelProps,
  CircularButton,
  horizontallyScrollChildVisible,
  HorizontalScrollableWithFades,
  makeRefHandler,
  MutableHtmlDivRefOrFunction,
  useActiveToolId,
  useFirstViewport,
  useHorizontalScrollChildVisibleOnResize,
  useScrolling,
} from "@itwin/mobile-ui-react";
import {
  PlaceMarkerTool,
  ImageMarkerApi,
} from "./Exports";

import "./ToolsBottomPanel.scss";
import { Messenger } from "@itwin/mobile-sdk-core";

export type ButtonRowProps = React.HTMLAttributes<HTMLDivElement>;

// tslint:disable-next-line: variable-name
export const ButtonRow = React.forwardRef((props: ButtonRowProps, ref: MutableHtmlDivRefOrFunction) => {
  const { className, children, ...nonChildren } = props;
  const divRef = React.useRef<HTMLDivElement | null>(null);
  const scrolling = useScrolling(divRef.current);

  return (
    <HorizontalScrollableWithFades
      {...nonChildren}
      scrollableClassName={classnames("button-row", className, scrolling && "scrolling")}
      fadesClassName="button-row-fades"
      onSetScrollable={(scrollable) => {
        divRef.current = scrollable;
        assignRef(ref, scrollable);
      }}
    >
      {children && <div className="button-spacer" />}
      {children}
      {children && <div className="button-spacer" />}
    </HorizontalScrollableWithFades>
  );
});

export interface ActiveButtonRowProps extends ButtonRowProps {
  activeIndex?: number;
}

// tslint:disable-next-line: variable-name
export const ActiveButtonRow = React.forwardRef((props: ActiveButtonRowProps, ref: MutableHtmlDivRefOrFunction) => {
  const { activeIndex, ...others } = props;
  const divRef = React.useRef<HTMLDivElement | null>(null);

  useHorizontalScrollChildVisibleOnResize(divRef.current, activeIndex !== undefined && activeIndex >= 0 ? activeIndex + 1 : undefined);

  return <ButtonRow ref={makeRefHandler(ref, divRef)} {...others} />;
});

export interface ToolsBottomPanelProps extends BottomPanelProps {
  /// The loaded iModel.
  iModel: IModelConnection;

  /// Optional callback that is called after a tool is selected.
  onToolClick?: () => void;
}

// Copied from ToolItemDef but fixed so the args work properly. Develoer notified and it will get fixed in iTwin.js 3.0.
function getItemDefForTool(tool: typeof Tool, iconSpec?: string, ...args: any[]): ToolItemDef {
  return new ToolItemDef({
    toolId: tool.toolId,
    iconSpec: iconSpec ? iconSpec : (tool.iconSpec && tool.iconSpec.length > 0) ? tool.iconSpec : undefined,
    label: () => tool.flyover,
    description: () => tool.description,
    execute: () => { IModelApp.tools.run(tool.toolId, ...args); },
  });
}

export class ImageLocations {
  public static getLocation(fileUrl: string) {
    const val = localStorage.getItem(fileUrl);
    if (!val)
      return undefined;
    return Point3d.fromJSON(JSON.parse(val));
  }

  public static setLocation(fileUrl: string, point: Point3d) {
    localStorage.setItem(fileUrl, JSON.stringify(point.toJSON()));
  }

  public static clearLocation(fileUrl: string) {
    localStorage.removeItem(fileUrl);
  }

  private static getImageCacheKeys() {
    const urls = new Array<string>();
    for (let i = 0; i < localStorage.length; ++i) {
      const key = localStorage.key(i);
      if (key) {
        const val = localStorage.getItem(key);
        if (val && val.startsWith("com.bentley.itms-image-cache://")) {
          urls.push(key);
        }
      }
    }
    return urls;
  }

  public static clearAllLocations() {
    for (const removal of this.getImageCacheKeys()) {
      localStorage.removeItem(removal);
    }
  }

  public static getLocations() {
    const locations = new Map<string, Point3d>();
    const urls = this.getImageCacheKeys();
    for (const url of urls) {
      const point = this.getLocation(url);
      if (point)
        locations.set(url, point);
    }
    return locations;
  }
}

const addImageMarker = async (point: Point3d, sourceType: string, iModelId: string) => {
  const fileUrl = await Messenger.query("ImagePicker", { iModelId, sourceType });
  const image = await imageElementFromUrl(fileUrl);
  ImageLocations.setLocation(fileUrl, point);
  ImageMarkerApi.addMarker(point, image, fileUrl);
};

class PlacePhotoMarkerTool extends PlaceMarkerTool {
  public static toolId = "PlacePhotoMarkerTool";
  public static iconSpec = "icon-image";

  constructor(iModelId: string) {
    super(async (point: Point3d) => {
      await addImageMarker(point, "photoLibrary", iModelId);
    });
  }
}

class PlaceCameraMarkerTool extends PlaceMarkerTool {
  public static toolId = "PlaceCameraMarkerTool";
  public static iconSpec = "icon-camera";

  constructor(iModelId: string) {
    super(async (point: Point3d) => {
      await addImageMarker(point, "camera", iModelId);
    });
  }
}

export function ToolsBottomPanel(props: ToolsBottomPanelProps) {
  const { iModel, onToolClick, ...others } = props;
  const vp = useFirstViewport();

  React.useEffect(() => {
    if (!vp)
      return;

    PlacePhotoMarkerTool.register(IModelApp.i18n.registerNamespace("marker-pin-i18n-namespace"));
    PlaceCameraMarkerTool.register(IModelApp.i18n.registerNamespace("marker-pin-i18n-namespace"));
    ImageMarkerApi.startup();

    return () => {
      ImageMarkerApi.shutdown();
      IModelApp.tools.unRegister(PlacePhotoMarkerTool.toolId);
      IModelApp.tools.unRegister(PlaceCameraMarkerTool.toolId);
      IModelApp.i18n.unregisterNamespace("marker-pin-i18n-namespace");
    };
  }, [vp]);

  const tools = [
    { labelKey: "ReactApp:ToolsBottomPanel.Select", icon: "icon-gesture-touch", toolItemDef: CoreTools.selectElementCommand },
    { labelKey: "ReactApp:ToolsBottomPanel.Distance", icon: "icon-measure-distance", toolItemDef: MeasureToolDefinitions.measureDistanceToolCommand },
    { labelKey: "ReactApp:ToolsBottomPanel.Location", icon: "icon-measure-location", toolItemDef: MeasureToolDefinitions.measureLocationToolCommand },
    { labelKey: "ReactApp:ToolsBottomPanel.Area", icon: "icon-measure-2d", toolItemDef: MeasureToolDefinitions.measureAreaToolCommand },
    { labelKey: "ReactApp:ToolsBottomPanel.Radius", icon: "icon-measure-arc", toolItemDef: MeasureToolDefinitions.measureRadiusToolCommand },
    { labelKey: "ReactApp:ToolsBottomPanel.Angle", icon: "icon-measure-angle", toolItemDef: MeasureToolDefinitions.measureAngleToolCommand },
    { labelKey: "ReactApp:ToolsBottomPanel.Perpendicular", icon: "icon-measure-perpendicular", toolItemDef: MeasureToolDefinitions.measurePerpendicularToolCommand },
    { labelKey: "ReactApp:ToolsBottomPanel.Clear", icon: "icon-measure-clear", toolItemDef: MeasureToolDefinitions.clearMeasurementsToolCommand },
    { labelKey: "ReactApp:ToolsBottomPanel.Picture", icon: "icon-image", toolItemDef: getItemDefForTool(PlacePhotoMarkerTool, undefined, iModel?.iModelId) },
    { labelKey: "ReactApp:ToolsBottomPanel.Camera", icon: "icon-camera", toolItemDef: getItemDefForTool(PlaceCameraMarkerTool, undefined, iModel?.iModelId) },
  ];

  const activeToolId = useActiveToolId();
  const activeToolIndex = activeToolId !== undefined ? tools.findIndex((tool) => activeToolId === tool.toolItemDef.toolId) : undefined;
  const toolsRowRef = React.useRef<HTMLDivElement>(null);

  return <BottomPanel
    {...others}
    className="tools-bottom-panel"
    onOpen={() => {
      if (toolsRowRef.current && activeToolIndex !== undefined)
        horizontallyScrollChildVisible(toolsRowRef.current, activeToolIndex + 1);
    }}>
    <ActiveButtonRow ref={toolsRowRef}
      activeIndex={activeToolIndex}>
      {tools.map((value) => {
        return <CircularButton
          key={value.labelKey}
          className="tool-button"
          label={IModelApp.i18n.translate(value.labelKey)}
          iconSpec={/* value.toolItemDef.iconSpec ??  */value.icon}
          selected={activeToolId === value.toolItemDef.toolId}
          onClick={async () => {
            // Ensure the selectedView is the main viewport otherwise some tools won't execute as the selected view is incompatible.
            // This only applies when an app has more than one viewport, but does no harm.
            IModelApp.viewManager.setSelectedView(IModelApp.viewManager.getFirstOpenView());

            // Use the virtual cursor for locating elements other than the select tool
            ToolSettings.enableVirtualCursorForLocate = value.toolItemDef.toolId !== CoreTools.selectElementCommand.toolId;

            value.toolItemDef.execute();
            onToolClick?.();
          }}
        />;
      })}
    </ActiveButtonRow>
  </BottomPanel>;
}
