<%@ Page
    Language="VB"
    MasterPageFile="~/Skins/Site.master"
    AutoEventWireup="true"
    CodeFile="default.aspx.vb"
    Inherits="_Default" %>
<%@ Register TagPrefix="uc" TagName="Search" Src="~/Controls/Search.ascx" %>
<asp:Content runat="server">
    <uc:Search runat="server" ID="ucSearch" />
</asp:Content>
