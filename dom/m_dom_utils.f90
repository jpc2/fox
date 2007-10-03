 



module m_dom_utils

  use m_common_attrs, only: getValue
  use m_common_format, only: operator(//)
  use m_common_array_str, only: str_vs, vs_str

  use m_dom_dom, only: Node, Namednodemap, NodeList
  use m_dom_dom, only: DOCUMENT_NODE, ELEMENT_NODE, TEXT_NODE, &
   CDATA_SECTION_NODE, COMMENT_NODE, DOCUMENT_TYPE_NODE, &
   ATTRIBUTE_NODE, ENTITY_REFERENCE_NODE, PROCESSING_INSTRUCTION_NODE
  use m_dom_dom, only: haschildnodes, getNodeName, getNodeType, getFoX_checks, &
    getFirstChild, getNextSibling, getlength, item, getOwnerElement, getXmlStandalone, &
    getAttributes, getParentNode, getChildNodes, getPrefix, getLocalName, getXmlVersion, &
    getNodeName, getData, getName, getTagName, getValue, getTarget, getNamespaceNodes, &
    getEntities, getNotations, item, getSystemId, getPublicId, getNotationName, getStringValue, &
    getNamespaceURI, DOMConfiguration, getDomConfig, getParameter, getSpecified, getOwnerDocument
  use m_dom_error, only: DOMException, inException, throw_exception, &
    FoX_INVALID_NODE, SERIALIZE_ERR, FoX_INTERNAL_ERROR

  use FoX_wxml, only: xmlf_t
  use FoX_wxml, only: xml_OpenFile, xml_Close
  use FoX_wxml, only: xml_AddXMLDeclaration
  use FoX_wxml, only: xml_DeclareNamespace, xml_AddDOCTYPE, xml_AddInternalEntity
  use FoX_wxml, only: xml_AddAttribute, xml_AddExternalEntity, xml_AddNotation
  use FoX_wxml, only: xml_AddCharacters
  use FoX_wxml, only: xml_NewElement
  use FoX_wxml, only: xml_EndElement
  use FoX_wxml, only: xml_AddComment
  use FoX_wxml, only: xml_AddEntityReference
  use FoX_wxml, only: xml_AddXMLPI

  implicit none

  public :: dumpTree
  public :: serialize

  private

contains

  subroutine dumpTree(startNode)

    type(Node), pointer :: startNode   

    integer           :: indent_level

    indent_level = 0

    call dump2(startNode)

  contains

    recursive subroutine dump2(input)
      type(Node), pointer :: input
      type(Node), pointer :: temp
      type(NamedNodeMap), pointer :: attrs
      type(NodeList), pointer :: nsnodes
      integer :: i
      temp => input
      do while(associated(temp))
         write(*,"(3a,i0)") repeat(" ", indent_level), &
                        getNodeName(temp), " of type ", &
                        getNodeType(temp)
         if (getNodeType(temp)==ELEMENT_NODE) then
           write(*,"(2a)") repeat(" ", indent_level), &
                        "  ATTRIBUTES:"
           attrs => getAttributes(temp)
           do i = 1, getLength(attrs)
             write(*, "(2a)") repeat(" ", indent_level)//"  ", &
               getName(item(attrs, i-1))
           enddo
           write(*,"(2a)") repeat(" ", indent_level), &
                        "  IN-SCOPE NAMESPACES:"
           nsnodes => getNamespaceNodes(temp)
           do i = 1, getLength(nsnodes)
             write(*,"(4a)") repeat(" ", indent_level)//"  ", &
               getPrefix(item(nsnodes, i-1)), ':', &
               getNamespaceURI(item(nsnodes, i-1))
           enddo
         endif
         if (hasChildNodes(temp)) then
            indent_level = indent_level + 3
            call dump2(getFirstChild(temp))
            indent_level = indent_level - 3
         endif
         temp => getNextSibling(temp)
      enddo

    end subroutine dump2

  end subroutine dumpTree


  subroutine serialize(startNode, name, ex)
    type(DOMException), intent(out), optional :: ex
    type(Node), pointer :: startNode   
    character(len=*), intent(in) :: name

    type(Node), pointer :: doc
    type(xmlf_t)  :: xf
    integer :: iostat
    logical :: xmlDecl

    if (getNodeType(startNode)/=DOCUMENT_NODE &
      .and.getNodeType(startNode)/=ELEMENT_NODE) then
      if (getFoX_checks().or.FoX_INVALID_NODE<200) then
  call throw_exception(FoX_INVALID_NODE, "serialize", ex)
  if (present(ex)) then
    if (inException(ex)) then
       return
    endif
  endif
endif

    endif
    
    if (getNodeType(startNode)==DOCUMENT_NODE) then
      doc => startNode
      if (getParameter(getDomConfig(doc), "canonical-form") &
        .and.getXmlVersion(doc)=="1.1") then
        if (getFoX_checks().or.SERIALIZE_ERR<200) then
  call throw_exception(SERIALIZE_ERR, "serialize", ex)
  if (present(ex)) then
    if (inException(ex)) then
       return
    endif
  endif
endif

      endif
      call normalizeDocument(startNode)
    else
      doc => getOwnerDocument(startNode)
      ! We need to do this namespace fixup or serialization will fail.
      ! it doesn't change the semantics of the docs, but other
      ! normalization would, so dont
      if (getParameter(getDomConfig(doc), "namespaces")) &
        call namespaceFixup(startNode)
    endif
    xmlDecl = getParameter(getDomConfig(doc), "xml-declaration")

    ! FIXME we shouldnt really normalize the Document here
    ! (except for namespace Normalization) but rather just
    ! pay attention to the DOMConfig values

    call xml_OpenFile(name, xf, iostat=iostat, unit=-1, &
      preserve_whitespace=.not.getParameter(getDomConfig(doc), "format-pretty-print"), &
      warning=.false., addDecl=xmlDecl)
    if (iostat/=0) then
      if (getFoX_checks().or.SERIALIZE_ERR<200) then
  call throw_exception(SERIALIZE_ERR, "serialize", ex)
  if (present(ex)) then
    if (inException(ex)) then
       return
    endif
  endif
endif

    endif

    if (xmlDecl) then
      if (getXmlStandalone(doc)) then
        call xml_AddXMLDeclaration(xf, version=getXmlVersion(doc), standalone=.true.)
      else
        call xml_AddXMLDeclaration(xf, version=getXmlVersion(doc))
      endif
    endif

    call iter_dmp_xml(xf, startNode, ex)
    call xml_Close(xf)

  end subroutine serialize

  subroutine iter_dmp_xml(xf, arg, ex)
    type(DOMException), intent(out), optional :: ex
    type(xmlf_t), intent(inout) :: xf

    type(Node), pointer :: this, arg, treeroot, attrchild
    type(NamedNodeMap), pointer :: nnm
    type(DOMConfiguration), pointer :: dc
    integer :: i_tree, j
    logical :: doneChildren, doneAttributes
    character, pointer :: attrvalue(:), tmp(:)

    if (getNodeType(arg)==DOCUMENT_NODE) then
      dc => getDomConfig(arg)
    else
      dc => getDomConfig(getOwnerDocument(arg))
    endif

    treeroot => arg

    i_tree = 0
    doneChildren = .false.
    doneAttributes = .false.
    this => treeroot
    do

      if (.not.doneChildren.and..not.(getNodeType(this)==ELEMENT_NODE.and.doneAttributes)) then
    select case(getNodeType(this))
    case (ELEMENT_NODE)
      nnm => getAttributes(this)
      do j = 0, getLength(nnm) - 1
        attrchild => item(nnm, j)
        if (getLocalName(attrchild)=="xmlns") then
          call xml_DeclareNamespace(xf, getValue(attrchild))
        elseif (getPrefix(attrchild)=="xmlns") then
          call xml_DeclareNamespace(xf, getValue(attrchild), &
            getLocalName(attrchild))
        endif
      enddo
      call xml_NewElement(xf, getTagName(this))
    case (ATTRIBUTE_NODE)
      if (.not.getParameter(dc, "discard-default_attributes") &
        .or.getSpecified(this)) then
        ! only output it if it is not a default, or we are outputting defaults
        ! we might have to worry about entrefs being preserved in the attvalue
        ! if we dont, we only go through the loop once anyway.
        do j = 0, getLength(getChildNodes(this)) - 1
          attrchild => item(getChildNodes(this), j)
          if (getNodeType(attrchild)==TEXT_NODE) then
            tmp => attrvalue
            allocate(attrvalue(size(tmp)+getLength(attrchild)))
            attrvalue(:size(tmp)) = tmp
            attrvalue(size(tmp)+1:) = vs_str(getData(attrChild))
            deallocate(tmp)
          elseif (getNodeType(attrchild)==ENTITY_REFERENCE_NODE) then
            tmp => attrvalue
            allocate(attrvalue(size(tmp)+len(getNodeName(attrchild))+2))
            attrvalue(:size(tmp)) = tmp
            attrvalue(size(tmp)+1:) = vs_str("&"//getData(attrChild)//";")
            deallocate(tmp)
          else
            if (getFoX_checks().or.FoX_INTERNAL_ERROR<200) then
  call throw_exception(FoX_INTERNAL_ERROR, "iter_dmp_xml", ex)
  if (present(ex)) then
    if (inException(ex)) then
       return
    endif
  endif
endif

          endif
        enddo
        call xml_AddAttribute(xf, getName(this), str_vs(attrvalue))
        deallocate(attrvalue)
      endif
      doneChildren = .true.
    case (TEXT_NODE)
      call xml_AddCharacters(xf, getData(this))
    case (CDATA_SECTION_NODE)
      call xml_AddCharacters(xf, getData(this), parsed = .false.)
    case (ENTITY_REFERENCE_NODE)
      call xml_AddEntityReference(xf, getNodeName(this))
      doneChildren = .true.
    case (PROCESSING_INSTRUCTION_NODE)
      call xml_AddXMLPI(xf, getTarget(this), getData(this))
    case (COMMENT_NODE)
      call xml_AddComment(xf, getData(this))
    case (DOCUMENT_TYPE_NODE)
      call xml_AddDOCTYPE(xf, getName(this))
      nnm => getNotations(this)
      do j = 0, getLength(nnm)-1
        if (getSystemId(item(nnm, j))=="") then
          call xml_AddNotation(xf, getNodeName(item(nnm, j)), public=getPublicId(item(nnm, j)))
        elseif (getPublicId(item(nnm, j))=="") then
          call xml_AddNotation(xf, getNodeName(item(nnm, j)), system=getSystemId(item(nnm, j)))
        else
          call xml_AddNotation(xf, getNodeName(item(nnm, j)), system=getSystemId(item(nnm, j)), &
            public=getPublicId(item(nnm, j)))
        endif
      enddo
      nnm => getEntities(this)
      do j = 0, getLength(nnm)-1
        if (getSystemId(item(nnm, j))=="") then
          call xml_AddInternalEntity(xf, getNodeName(item(nnm, j)), getStringValue(item(nnm, j)))
        elseif (getPublicId(item(nnm, j))=="".and.getNotationName(item(nnm, j))=="") then
          call xml_AddExternalEntity(xf, getNodeName(item(nnm, j)), system=getSystemId(item(nnm, j)))
        elseif (getNotationName(item(nnm, j))=="") then
          call xml_AddExternalEntity(xf, getNodeName(item(nnm, j)), system=getSystemId(item(nnm, j)), &
            public=getPublicId(item(nnm, j)))
        elseif (getPublicId(item(nnm, j))=="") then
          call xml_AddExternalEntity(xf, getNodeName(item(nnm, j)), system=getSystemId(item(nnm, j)), &
            notation=getNotationName(item(nnm, j)))
        else
          call xml_AddExternalEntity(xf, getNodeName(item(nnm, j)), system=getSystemId(item(nnm, j)), &
            public=getPublicId(item(nnm, j)), notation=getNotationName(item(nnm, j)))
        endif
      enddo
    end select

      else
        if (getNodeType(this)==ELEMENT_NODE.and..not.doneChildren) then
          doneAttributes = .true.
        else

    if (getNodeType(this)==ELEMENT_NODE) then
      call xml_EndElement(xf, getTagName(this))
    endif

        endif
      endif


      if (.not.doneChildren) then
        if (getNodeType(this)==ELEMENT_NODE.and..not.doneAttributes) then
          if (getLength(getAttributes(this))>0) then
                      this => item(getAttributes(this), 0)
          else
            doneAttributes = .true.
          endif
        elseif (hasChildNodes(this)) then
          this => getFirstChild(this)
          doneChildren = .false.
          doneAttributes = .false.
        else
          doneChildren = .true.
          doneAttributes = .false.
        endif

      else ! if doneChildren

        if (associated(this, treeroot)) exit
        if (getNodeType(this)==ATTRIBUTE_NODE) then
          if (i_tree<getLength(getAttributes(getOwnerElement(this)))-1) then
            i_tree= i_tree+ 1
            this => item(getAttributes(getOwnerElement(this)), i_tree)
            doneChildren = .false.
          else
            i_tree= 0
            this => getOwnerElement(this)
            doneAttributes = .true.
            doneChildren = .false.
          endif
        elseif (associated(getNextSibling(this))) then

          this => getNextSibling(this)
          doneChildren = .false.
          doneAttributes = .false.
        else
          this => getParentNode(this)
        endif
      endif

    enddo



  end subroutine iter_dmp_xml

end module m_dom_utils
