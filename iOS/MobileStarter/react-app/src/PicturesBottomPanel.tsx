/*---------------------------------------------------------------------------------------------
* Copyright (c) Bentley Systems, Incorporated. All rights reserved.
* See LICENSE.md in the project root for license terms and full copyright notice.
*--------------------------------------------------------------------------------------------*/
import React from "react";
import ReactDOM from "react-dom";
import classnames from "classnames";
import { IModelConnection } from "@bentley/imodeljs-frontend";
import {
  MobileCore,
  presentYesNoAlert,
  ReloadedEvent,
} from "@itwin/mobile-sdk-core";
import { DraggableComponent, NavigationButton, ResizableBottomPanel, ResizableBottomPanelProps, ToolButton, useUiEvent } from "@itwin/mobile-ui-react";
import { HeaderTitle, i18n, ImageCache, ImageMarkerApi } from "./Exports";

import "./PicturesBottomPanel.scss";

/// Properties for the [[PicturesBottomPanel]] React component.
export interface PicturesBottomPanelProps extends ResizableBottomPanelProps {
  /// The loaded iModel.
  iModel: IModelConnection;
  /// Optional callback that is called after a picture is selected.
  onPictureSelected?: (pictureUrl: string) => void;
}

/** [[ResizableBottomPanel]] React component that allows the user to take pictures with the device's camera.
 * 
 * Shows the pictures that have been taken for the selected iModel. Allows the user to take more, as well as
 * delete individual pictures or all pictures.
 */
export function PicturesBottomPanel(props: PicturesBottomPanelProps) {
  const { iModel, onPictureSelected, ...otherProps } = props;
  const picturesLabel = React.useMemo(() => i18n("PicturesBottomPanel", "Pictures"), []);
  const reloadedEvent = React.useRef(new ReloadedEvent());
  const [pictureUrls, setPictureUrls] = React.useState<string[]>([]);
  const deletePictureTitle = React.useMemo(() => i18n("PicturesBottomPanel", "DeletePictureTitle"), []);
  const deletePictureMessage = React.useMemo(() => i18n("PicturesBottomPanel", "DeletePictureMessage"), []);
  const deleteAllTitle = React.useMemo(() => i18n("PicturesBottomPanel", "DeleteAllTitle"), []);
  const deleteAllMessage = React.useMemo(() => i18n("PicturesBottomPanel", "DeleteAllMessage"), []);
  const deleteSelectedTitle = React.useMemo(() => i18n("PicturesBottomPanel", "DeleteSelectedTitle"), []);
  const deleteSelectedMessage = React.useMemo(() => i18n("PicturesBottomPanel", "DeleteSelectedMessage"), []);
  const [decoratorActive, setDecoratorActive] = React.useState(true);
  const [selectMode, setSelectMode] = React.useState(false);
  const [selectedUrls, setSelectedUrls] = React.useState(new Set<string>());

  const reload = React.useCallback(async () => {
    const urls = await ImageCache.getImages(iModel.iModelId);
    urls.sort();
    setPictureUrls(urls);
    if (urls.length === 0) {
      setSelectMode(false);
      setSelectedUrls(new Set<string>());
    }
    reloadedEvent.current.emit();
  }, [iModel]);

  React.useEffect(() => {
    reload();
  }, [reload]);

  useUiEvent(() => reload(), ImageMarkerApi.onMarkerAdded);

  const togglePictureSelected = React.useCallback((pictureUrl: string) => {
    setSelectedUrls((previousSelectedUrls) => {
      const newSelected = new Set<string>(previousSelectedUrls);
      if (newSelected.has(pictureUrl))
        newSelected.delete(pictureUrl);
      else
        newSelected.add(pictureUrl);
      return newSelected;
    })
  }, []);

  const handlePictureClick = React.useCallback((pictureUrl: string) => {
    if (selectMode) {
      togglePictureSelected(pictureUrl);
    } else {
      onPictureSelected?.(pictureUrl);
    }
  }, [onPictureSelected, selectMode, togglePictureSelected]);

  const pictureButtons = pictureUrls.map((pictureUrl, index) => {
    const selected = selectedUrls.has(pictureUrl);
    return (
      <div className={classnames("list-item", selectMode && selected && "selected")} key={index} onClick={() => handlePictureClick(pictureUrl)}>
        <img src={pictureUrl} alt="" />
        {!selectMode && <NavigationButton
          className="delete-button"
          iconSpec={"icon-delete"}
          onClick={async () => {
            if (await presentYesNoAlert(deletePictureTitle, deletePictureMessage, true)) {
              await ImageCache.deleteImages([pictureUrl]);
              reload();
            }
          }}
        />}
        {selectMode && selected && <NavigationButton
          className="select-button"
          iconSpec={"icon-checkmark"}
        />}
      </div>
    );
  });

  // Add 10 0-height dummy items after the real items to force the last row to be left-justified.
  const dummyItems: React.ReactNode[] = [];
  for (let i = 0; i < 10; ++i) {
    dummyItems.push(<div className="dummy-item" key={i + pictureUrls.length} />);
  }

  const headerMoreElements = (
    <div className="header-right">
      {pictureUrls.length > 0 && <NavigationButton
        style={{ color: (selectMode ? "var(--muic-active)" : "var(--muic-foreground)") }}
        iconSpec={"icon-checkmark"}
        noShadow
        onClick={() => {
          setSelectMode(!selectMode);
        }} />}
      {!selectMode && <>
        <ToolButton iconSpec={"icon-camera"} onClick={async () => {
          if (await ImageCache.pickImage(iModel.iModelId)) {
            reload();
          }
        }} />
        <ToolButton iconSpec={"icon-image"} onClick={async () => {
          if (await ImageCache.pickImage(iModel.iModelId, true)) {
            reload();
          }
        }} />
        <ToolButton iconSpec={decoratorActive ? "icon-visibility-hide-2" : "icon-visibility"} onClick={() => {
          ImageMarkerApi.enabled = !ImageMarkerApi.enabled;
          setDecoratorActive(ImageMarkerApi.enabled);
        }} />
      </>}
      {selectMode && <>
        <ToolButton iconSpec={"icon-checkbox-select"} enabled={selectedUrls.size !== pictureUrls.length} onClick={() => {
          setSelectedUrls(new Set(pictureUrls));
        }} />
        <ToolButton iconSpec={"icon-checkbox-deselect"} enabled={selectedUrls.size > 0} onClick={() => {
          setSelectedUrls(new Set());
        }} />
        <ToolButton iconSpec={MobileCore.isIosPlatform ? "icon-upload" : "icon-share"} enabled={selectedUrls.size > 0}
          onClick={(e) => {
            ImageCache.shareImages(Array.from(selectedUrls), e.currentTarget.getBoundingClientRect());
          }} />
        <ToolButton
          iconSpec={"icon-delete"}
          enabled={selectedUrls.size > 0}
          onClick={async () => {
            const all = pictureUrls.length === selectedUrls.size;
            if (all && await presentYesNoAlert(deleteAllTitle, deleteAllMessage, true)) {
              await ImageCache.deleteAllImages(iModel.iModelId);
              reload();
            } else if (!all && await presentYesNoAlert(deleteSelectedTitle, deleteSelectedMessage, true)) {
              await ImageCache.deleteImages(Array.from(selectedUrls));
              reload();
            }
          }}
        />
      </>}
    </div>
  );

  return (
    <ResizableBottomPanel
      {...otherProps}
      className="pictures-bottom-panel"
      header={<DraggableComponent className="resizable-panel-header">
        <HeaderTitle
          label={picturesLabel}
          iconSpec="icon-saved-view"
          moreElements={headerMoreElements}
        />
      </DraggableComponent>}
      reloadedEvent={reloadedEvent.current}
    >
      <div className="list">
        <div className="list-items">
          {pictureButtons}
          {dummyItems}
        </div>
      </div>
    </ResizableBottomPanel>
  );
}

export interface PictureViewProps {
  url: string;
  onClick?: (e: React.MouseEvent<HTMLDivElement>) => void;
}

export function PictureView(props: PictureViewProps) {
  const { url, onClick } = props;
  const portalDiv = (
    <div className="picture-view">
      <img src={url} onClick={onClick} alt="" />
    </div>
  );
  const rootElement = document.getElementById("root");
  return ReactDOM.createPortal(portalDiv, rootElement!);
}
