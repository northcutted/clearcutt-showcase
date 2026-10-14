/*
 * catalog._feeds: validate supplier XML feeds with libxml2.
 *
 * Linked against the system libxml2 (libxml2.so.2 for 2.13 and earlier,
 * libxml2.so.16 from 2.14), so the app depends on the run image providing the
 * same soname it was built against. That is what makes catalog the app whose
 * rebase is refused when the platform moves libxml2 across that line.
 */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlversion.h>

static PyObject *
feeds_validate(PyObject *self, PyObject *args)
{
    const char *buf;
    Py_ssize_t len;
    if (!PyArg_ParseTuple(args, "y#", &buf, &len))
        return NULL;
    if (len > INT_MAX) {
        PyErr_SetString(PyExc_ValueError, "feed too large");
        return NULL;
    }
    /* No network, no entity expansion, no DTD loading: supplier feeds are untrusted. */
    xmlDocPtr doc = xmlReadMemory(buf, (int)len, "feed.xml", NULL, XML_PARSE_NONET | XML_PARSE_NOERROR | XML_PARSE_NOWARNING);
    if (doc == NULL) {
        const xmlError *err = xmlGetLastError();
        return Py_BuildValue("(Os)", Py_False, err && err->message ? err->message : "not well-formed XML");
    }
    xmlNodePtr root = xmlDocGetRootElement(doc);
    long items = 0;
    if (root != NULL) {
        for (xmlNodePtr n = root->children; n != NULL; n = n->next)
            if (n->type == XML_ELEMENT_NODE && xmlStrcmp(n->name, (const xmlChar *)"item") == 0)
                items++;
    }
    int is_feed = root != NULL && xmlStrcmp(root->name, (const xmlChar *)"feed") == 0;
    xmlFreeDoc(doc);
    if (!is_feed)
        return Py_BuildValue("(Os)", Py_False, "root element is not <feed>");
    return Py_BuildValue("(Ol)", Py_True, items);
}

static PyObject *
feeds_libxml_version(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    /* Compiled-against version, and the version of the library actually loaded. */
    return Py_BuildValue("(ss)", LIBXML_DOTTED_VERSION, xmlParserVersion);
}

static PyMethodDef feeds_methods[] = {
    {"validate", feeds_validate, METH_VARARGS, "validate(feed: bytes) -> (ok, item count or error)"},
    {"libxml_version", feeds_libxml_version, METH_NOARGS, "(compiled, loaded) libxml2 versions"},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef feeds_module = {
    PyModuleDef_HEAD_INIT, "catalog._feeds", "Supplier feed validation (libxml2).", -1, feeds_methods,
};

PyMODINIT_FUNC
PyInit__feeds(void)
{
    xmlInitParser();
    return PyModule_Create(&feeds_module);
}
