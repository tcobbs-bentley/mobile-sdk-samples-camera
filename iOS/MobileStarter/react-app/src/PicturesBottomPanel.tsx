/*---------------------------------------------------------------------------------------------
* Copyright (c) Bentley Systems, Incorporated. All rights reserved.
* See LICENSE.md in the project root for license terms and full copyright notice.
*--------------------------------------------------------------------------------------------*/
import React from "react";
import ReactDOM from "react-dom";
import { IModelConnection } from "@bentley/imodeljs-frontend";
import { ActionStyle, Messenger, presentAlert, ReloadedEvent } from "@itwin/mobile-sdk-core";
import { DraggableComponent, NavigationButton, ResizableBottomPanel, ResizableBottomPanelProps } from "@itwin/mobile-ui-react";
import { HeaderTitle, i18n } from "./Exports";

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
  const [selectedPictureUrl, setSelectedPictureUrl] = React.useState<string>();

  const reload = React.useCallback(async () => {
    const urls: string[] = await Messenger.query("getImages", { iModelId: iModel.iModelId });
    urls.sort();
    setPictureUrls(urls);
    reloadedEvent.current.emit();
  }, [iModel]);

  React.useEffect(() => {
    reload();
  }, [reload]);

  const handlePictureSelected = React.useCallback((pictureUrl: string) => {
    setSelectedPictureUrl(pictureUrl);
    onPictureSelected?.(pictureUrl);
  }, [onPictureSelected]);

  const pictureButtons = pictureUrls.map((pictureUrl, index) => {
    return (
      <div className="list-item" key={index} onClick={() => handlePictureSelected(pictureUrl)}>
        <img src={pictureUrl} alt="" />
        <NavigationButton
          className="delete-button"
          iconSpec={"icon-delete"}
          onClick={async () => {
            await Messenger.query("deleteImage", { url: pictureUrl });
            reload();
          }}
        />
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
      <NavigationButton
        iconSpec={"icon-delete"}
        enabled={pictureUrls.length > 0}
        onClick={async () => {
          const response = await presentAlert({
            title: i18n("PicturesBottomPanel", "DeleteAllTitle"),
            message: i18n("PicturesBottomPanel", "DeleteAllMessage"),
            actions: [{
              name: "yes",
              title: i18n("Shared", "Yes"),
              style: ActionStyle.Destructive,
            },
            {
              name: "no",
              title: i18n("Shared", "No"),
            }],
          });
          if (response === "yes") {
            await Messenger.query("deleteImages", { iModelId: iModel.iModelId });
            reload();
          }
        }}
      />
      <NavigationButton iconSpec={"icon-add"} onClick={async () => {
        await Messenger.query("ImagePicker", { iModelId: iModel.iModelId });
        reload();
      }} />
    </div>
  );

  const handlePictureViewClick = React.useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    e.stopPropagation();
    setSelectedPictureUrl(undefined);
  }, []);

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
      {selectedPictureUrl && <PictureView url={selectedPictureUrl} onClick={handlePictureViewClick} />}
    </ResizableBottomPanel>
  );
}

interface PictureViewProps {
  url: string;
  onClick?: (e: React.MouseEvent<HTMLDivElement>) => void;
}

function PictureView(props: PictureViewProps) {
  const { url, onClick } = props;
  const portalDiv = (
    <div className="picture-view">
      <img src={url} onClick={onClick} alt="" />
    </div>
  );
  const rootElement = document.getElementById("root");
  return ReactDOM.createPortal(portalDiv, rootElement!);
}
